import { VaultCrypto, SealedVaultData, VaultLockedException } from '../../core/crypto/vaultCrypto';
import { SecretStore, LocalSecretStore } from '../../core/storage/secretStore';
import { VaultItem, VaultItemKind } from '../../types';
import { VaultSessionManager, ActiveVaultSession } from './vaultSession';

export class MissingVaultKeyException extends Error {
  constructor(message = 'Vault master key is missing or vault is locked.') {
    super(message);
    this.name = 'MissingVaultKeyException';
  }
}

export class VaultFormatException extends Error {
  constructor(message = 'Vault item format is invalid.') {
    super(message);
    this.name = 'VaultFormatException';
  }
}

export class VaultCorruptedKeyException extends Error {
  constructor(message = 'Dữ liệu khóa của kho bị lỗi hoặc không thể đọc được. Không thể tiếp tục để tránh làm mất dữ liệu.') {
    super(message);
    this.name = 'VaultCorruptedKeyException';
  }
}

interface EncryptedVaultRecord {
  id: string;
  v: number;
  nonce: string; // base64
  mac: string; // base64
  cipherText: string; // base64
  metaNonce: string;
  metaMac: string;
  metaCipherText: string;
  createdAt: string;
  size: number;
}

interface WrappedKeyRecord {
  v: 2;
  salt: string; // hex
  nonce: string; // base64
  mac: string; // base64
  wrappedKey: string; // base64
  iterations: number;
}

export class VaultKeyStore {
  private static WRAPPED_KEY = 'vault_wrapped_key_v2';
  private static LEGACY_KEY = 'vault_master_key_v1';
  private store: SecretStore;
  private crypto: VaultCrypto;

  constructor(store: SecretStore = new LocalSecretStore(), crypto: VaultCrypto = new VaultCrypto()) {
    this.store = store;
    this.crypto = crypto;
  }

  async hasConfiguredKey(): Promise<boolean> {
    const wrapped = await this.store.read(VaultKeyStore.WRAPPED_KEY);
    if (wrapped) return true;
    const legacy = await this.store.read(VaultKeyStore.LEGACY_KEY);
    return legacy !== null;
  }

  /**
   * Provisions a brand new master key wrapped with the provided PIN.
   */
  async provision(pin: string): Promise<ActiveVaultSession> {
    const saltBytes = crypto.getRandomValues(new Uint8Array(16));
    const saltHex = Array.from(saltBytes).map(b => b.toString(16).padStart(2, '0')).join('');
    const kek = await this.crypto.deriveKek(pin, saltBytes, 100000);

    const masterKey = await this.crypto.newKey();
    const wrapped = await this.crypto.wrapKey(masterKey, kek);

    const record: WrappedKeyRecord = {
      v: 2,
      salt: saltHex,
      nonce: this.crypto.bytesToBase64(wrapped.nonce),
      mac: this.crypto.bytesToBase64(wrapped.mac),
      wrappedKey: this.crypto.bytesToBase64(wrapped.cipherText),
      iterations: 100000,
    };

    await this.store.write(VaultKeyStore.WRAPPED_KEY, JSON.stringify(record));
    return VaultSessionManager.getInstance().startSession(masterKey);
  }

  /**
   * Unwraps the master key with PIN and returns an active session.
   * Performs atomic migration if legacy raw key is present.
   */
  async unlock(pin: string): Promise<ActiveVaultSession> {
    const wrappedRaw = await this.store.read(VaultKeyStore.WRAPPED_KEY);
    if (wrappedRaw) {
      try {
        const record: WrappedKeyRecord = JSON.parse(wrappedRaw);
        const saltBytes = this.hexToBytes(record.salt);
        const kek = await this.crypto.deriveKek(pin, saltBytes, record.iterations || 100000);
        const sealed: SealedVaultData = {
          cipherText: this.crypto.base64ToBytes(record.wrappedKey),
          nonce: this.crypto.base64ToBytes(record.nonce),
          mac: this.crypto.base64ToBytes(record.mac),
        };
        const masterKey = await this.crypto.unwrapKey(sealed, kek);
        return VaultSessionManager.getInstance().startSession(masterKey);
      } catch (err) {
        throw new VaultCorruptedKeyException();
      }
    }

    // Check for legacy raw key migration
    const legacyRaw = await this.store.read(VaultKeyStore.LEGACY_KEY);
    if (legacyRaw) {
      try {
        const legacyBytes = this.crypto.base64ToBytes(legacyRaw);
        const legacyMasterKey = await this.crypto.importKey(legacyBytes);

        // Migrate to wrapped key checkpoint
        const saltBytes = crypto.getRandomValues(new Uint8Array(16));
        const saltHex = Array.from(saltBytes).map(b => b.toString(16).padStart(2, '0')).join('');
        const kek = await this.crypto.deriveKek(pin, saltBytes, 100000);
        const wrapped = await this.crypto.wrapKey(legacyMasterKey, kek);

        const newRecord: WrappedKeyRecord = {
          v: 2,
          salt: saltHex,
          nonce: this.crypto.bytesToBase64(wrapped.nonce),
          mac: this.crypto.bytesToBase64(wrapped.mac),
          wrappedKey: this.crypto.bytesToBase64(wrapped.cipherText),
          iterations: 100000,
        };

        // Write wrapped record
        await this.store.write(VaultKeyStore.WRAPPED_KEY, JSON.stringify(newRecord));

        // Verify readback and unwrapping before deleting legacy key
        const readback = await this.store.read(VaultKeyStore.WRAPPED_KEY);
        if (!readback) throw new Error('Migration readback check failed');
        const readbackRecord: WrappedKeyRecord = JSON.parse(readback);
        const verifyKek = await this.crypto.deriveKek(pin, this.hexToBytes(readbackRecord.salt), 100000);
        await this.crypto.unwrapKey(
          {
            cipherText: this.crypto.base64ToBytes(readbackRecord.wrappedKey),
            nonce: this.crypto.base64ToBytes(readbackRecord.nonce),
            mac: this.crypto.base64ToBytes(readbackRecord.mac),
          },
          verifyKek
        );

        // Delete legacy raw key only after verification succeeded
        await this.store.delete(VaultKeyStore.LEGACY_KEY);

        return VaultSessionManager.getInstance().startSession(legacyMasterKey);
      } catch (err) {
        throw new VaultCorruptedKeyException();
      }
    }

    throw new MissingVaultKeyException();
  }

  private hexToBytes(hex: string): Uint8Array {
    const bytes = new Uint8Array(hex.length / 2);
    for (let i = 0; i < bytes.length; i++) {
      bytes[i] = parseInt(hex.substring(i * 2, i * 2 + 2), 16);
    }
    return bytes;
  }
}

export class LocalVaultRepository {
  private crypto: VaultCrypto;
  private sessionManager: VaultSessionManager;
  private dbName = 'private_vault_db_v1';
  private storeName = 'encrypted_items';
  private dbPromise: Promise<IDBDatabase> | null = null;

  constructor(sessionManager?: VaultSessionManager, crypto?: VaultCrypto) {
    this.crypto = crypto ?? new VaultCrypto();
    this.sessionManager = sessionManager ?? VaultSessionManager.getInstance();
  }

  private async getDb(): Promise<IDBDatabase> {
    if (this.dbPromise) return this.dbPromise;

    this.dbPromise = new Promise((resolve, reject) => {
      const request = indexedDB.open(this.dbName, 1);
      request.onupgradeneeded = () => {
        const db = request.result;
        if (!db.objectStoreNames.contains(this.storeName)) {
          db.createObjectStore(this.storeName, { keyPath: 'id' });
        }
      };
      request.onsuccess = () => resolve(request.result);
      request.onerror = () => reject(request.error);
    });

    return this.dbPromise;
  }

  async countItems(): Promise<number> {
    const db = await this.getDb();
    return new Promise<number>((resolve, reject) => {
      const tx = db.transaction(this.storeName, 'readonly');
      const store = tx.objectStore(this.storeName);
      const req = store.count();
      req.onsuccess = () => resolve(req.result);
      req.onerror = () => reject(req.error);
    });
  }

  private getRequiredSessionKey(): CryptoKey {
    const session = this.sessionManager.getActiveSession();
    if (!session || session.isRevoked) {
      throw new VaultLockedException('Kho dữ liệu đang bị khóa. Quyền truy cập bị từ chối.');
    }
    return session.getKey();
  }

  async addBytes(
    bytes: Uint8Array,
    options: {
      kind: VaultItemKind;
      name?: string;
      mimeType?: string;
      sourceHash?: string;
      album?: string;
      isFavorite?: boolean;
      thumbnail?: string;
      width?: number;
      height?: number;
      duration?: string;
    }
  ): Promise<VaultItem> {
    if (options.kind === 'unknown') {
      throw new Error('Unknown kind cannot be persisted');
    }

    const key = this.getRequiredSessionKey();
    const id = this.generateId();
    const createdAt = new Date().toISOString();

    const sealedPayload = await this.crypto.encrypt(bytes, key);

    const metaClear = new TextEncoder().encode(
      JSON.stringify({
        id,
        kind: options.kind,
        name: options.name || `item-${id.slice(0, 8)}`,
        mimeType: options.mimeType,
        sourceHash: options.sourceHash,
        createdAt,
        size: bytes.byteLength,
        album: options.album || 'default',
        isFavorite: options.isFavorite || false,
        thumbnail: options.thumbnail,
        width: options.width,
        height: options.height,
        duration: options.duration,
      })
    );
    const sealedMeta = await this.crypto.encrypt(metaClear, key);

    const record: EncryptedVaultRecord = {
      id,
      v: 1,
      nonce: this.crypto.bytesToBase64(sealedPayload.nonce),
      mac: this.crypto.bytesToBase64(sealedPayload.mac),
      cipherText: this.crypto.bytesToBase64(sealedPayload.cipherText),
      metaNonce: this.crypto.bytesToBase64(sealedMeta.nonce),
      metaMac: this.crypto.bytesToBase64(sealedMeta.mac),
      metaCipherText: this.crypto.bytesToBase64(sealedMeta.cipherText),
      createdAt,
      size: bytes.byteLength,
    };

    const db = await this.getDb();
    // A11 fix: wait for tx.oncomplete, handle abort and error
    await new Promise<void>((resolve, reject) => {
      const tx = db.transaction(this.storeName, 'readwrite');
      const store = tx.objectStore(this.storeName);
      store.put(record);
      tx.oncomplete = () => resolve();
      tx.onabort = () => reject(new Error('IndexedDB transaction aborted during addBytes'));
      tx.onerror = () => reject(tx.error);
    });

    return {
      id,
      kind: options.kind,
      name: options.name,
      mimeType: options.mimeType,
      sourceHash: options.sourceHash,
      size: bytes.byteLength,
      createdAt,
      album: options.album || 'default',
      isFavorite: options.isFavorite || false,
      thumbnail: options.thumbnail,
      width: options.width,
      height: options.height,
      duration: options.duration,
    };
  }

  async readBytes(
    id: string
  ): Promise<{ bytes: Uint8Array; kind: VaultItemKind; name: string; mimeType?: string; createdAt: string }> {
    const key = this.getRequiredSessionKey();
    const db = await this.getDb();

    const record = await new Promise<EncryptedVaultRecord | undefined>((resolve, reject) => {
      const tx = db.transaction(this.storeName, 'readonly');
      const store = tx.objectStore(this.storeName);
      const req = store.get(id);
      req.onsuccess = () => resolve(req.result as EncryptedVaultRecord);
      req.onerror = () => reject(req.error);
    });

    if (!record) {
      throw new VaultFormatException('Item not found in encrypted storage');
    }

    const metaSealed: SealedVaultData = {
      nonce: this.crypto.base64ToBytes(record.metaNonce),
      mac: this.crypto.base64ToBytes(record.metaMac),
      cipherText: this.crypto.base64ToBytes(record.metaCipherText),
    };
    const metaBytes = await this.crypto.decrypt(metaSealed, key);
    const meta = JSON.parse(new TextDecoder().decode(metaBytes));

    const payloadSealed: SealedVaultData = {
      nonce: this.crypto.base64ToBytes(record.nonce),
      mac: this.crypto.base64ToBytes(record.mac),
      cipherText: this.crypto.base64ToBytes(record.cipherText),
    };
    const payloadBytes = await this.crypto.decrypt(payloadSealed, key);

    return {
      bytes: payloadBytes,
      kind: meta.kind,
      name: meta.name || `item-${id.slice(0, 8)}`,
      mimeType: meta.mimeType,
      createdAt: meta.createdAt,
    };
  }

  async list(): Promise<VaultItem[]> {
    const key = this.getRequiredSessionKey();
    const db = await this.getDb();

    const records = await new Promise<EncryptedVaultRecord[]>((resolve, reject) => {
      const tx = db.transaction(this.storeName, 'readonly');
      const store = tx.objectStore(this.storeName);
      const req = store.getAll();
      req.onsuccess = () => resolve(req.result as EncryptedVaultRecord[]);
      req.onerror = () => reject(req.error);
    });

    const items: VaultItem[] = [];
    for (const record of records) {
      try {
        const metaSealed: SealedVaultData = {
          nonce: this.crypto.base64ToBytes(record.metaNonce),
          mac: this.crypto.base64ToBytes(record.metaMac),
          cipherText: this.crypto.base64ToBytes(record.metaCipherText),
        };
        const metaBytes = await this.crypto.decrypt(metaSealed, key);
        const meta = JSON.parse(new TextDecoder().decode(metaBytes));
        items.push({
          id: record.id,
          kind: meta.kind || 'unknown',
          name: meta.name,
          mimeType: meta.mimeType,
          sourceHash: meta.sourceHash,
          size: record.size,
          createdAt: meta.createdAt || record.createdAt,
          album: meta.album || 'default',
          isFavorite: !!meta.isFavorite,
          thumbnail: meta.thumbnail,
          width: meta.width,
          height: meta.height,
          duration: meta.duration,
        });
      } catch {
        items.push({
          id: record.id,
          kind: 'unknown',
          createdAt: record.createdAt,
        });
      }
    }

    items.sort((a, b) => new Date(b.createdAt).getTime() - new Date(a.createdAt).getTime());
    return items;
  }

  /**
   * Atomic update for note content: re-encrypts payload and title in a single transaction.
   * If any step fails, the previous note remains intact (A04 fix).
   */
  async updateNoteContent(id: string, newBytes: Uint8Array, newTitle: string): Promise<void> {
    const key = this.getRequiredSessionKey();
    const db = await this.getDb();

    const record = await new Promise<EncryptedVaultRecord | undefined>((resolve, reject) => {
      const tx = db.transaction(this.storeName, 'readonly');
      const store = tx.objectStore(this.storeName);
      const req = store.get(id);
      req.onsuccess = () => resolve(req.result as EncryptedVaultRecord);
      req.onerror = () => reject(req.error);
    });

    if (!record) {
      throw new VaultFormatException('Note not found to update');
    }

    // Decrypt existing metadata to preserve fields
    const metaSealed: SealedVaultData = {
      nonce: this.crypto.base64ToBytes(record.metaNonce),
      mac: this.crypto.base64ToBytes(record.metaMac),
      cipherText: this.crypto.base64ToBytes(record.metaCipherText),
    };
    const metaBytes = await this.crypto.decrypt(metaSealed, key);
    const meta = JSON.parse(new TextDecoder().decode(metaBytes));

    // Encrypt new payload
    const sealedPayload = await this.crypto.encrypt(newBytes, key);

    // Update metadata
    meta.name = newTitle;
    meta.size = newBytes.byteLength;
    meta.updatedAt = new Date().toISOString();

    const sealedMeta = await this.crypto.encrypt(new TextEncoder().encode(JSON.stringify(meta)), key);

    record.nonce = this.crypto.bytesToBase64(sealedPayload.nonce);
    record.mac = this.crypto.bytesToBase64(sealedPayload.mac);
    record.cipherText = this.crypto.bytesToBase64(sealedPayload.cipherText);
    record.metaNonce = this.crypto.bytesToBase64(sealedMeta.nonce);
    record.metaMac = this.crypto.bytesToBase64(sealedMeta.mac);
    record.metaCipherText = this.crypto.bytesToBase64(sealedMeta.cipherText);
    record.size = newBytes.byteLength;

    // Single atomic write awaiting tx.oncomplete
    await new Promise<void>((resolve, reject) => {
      const tx = db.transaction(this.storeName, 'readwrite');
      const store = tx.objectStore(this.storeName);
      store.put(record);
      tx.oncomplete = () => resolve();
      tx.onabort = () => reject(new Error('Transaction aborted during atomic note update'));
      tx.onerror = () => reject(tx.error);
    });
  }

  async updateMeta(id: string, updates: Partial<VaultItem>): Promise<void> {
    const key = this.getRequiredSessionKey();
    const db = await this.getDb();

    const record = await new Promise<EncryptedVaultRecord | undefined>((resolve, reject) => {
      const tx = db.transaction(this.storeName, 'readonly');
      const store = tx.objectStore(this.storeName);
      const req = store.get(id);
      req.onsuccess = () => resolve(req.result as EncryptedVaultRecord);
      req.onerror = () => reject(req.error);
    });

    if (!record) return;

    const metaSealed: SealedVaultData = {
      nonce: this.crypto.base64ToBytes(record.metaNonce),
      mac: this.crypto.base64ToBytes(record.metaMac),
      cipherText: this.crypto.base64ToBytes(record.metaCipherText),
    };
    const metaBytes = await this.crypto.decrypt(metaSealed, key);
    const meta = JSON.parse(new TextDecoder().decode(metaBytes));

    const updatedMeta = { ...meta, ...updates };
    const metaClear = new TextEncoder().encode(JSON.stringify(updatedMeta));
    const sealedMeta = await this.crypto.encrypt(metaClear, key);

    record.metaNonce = this.crypto.bytesToBase64(sealedMeta.nonce);
    record.metaMac = this.crypto.bytesToBase64(sealedMeta.mac);
    record.metaCipherText = this.crypto.bytesToBase64(sealedMeta.cipherText);

    await new Promise<void>((resolve, reject) => {
      const tx = db.transaction(this.storeName, 'readwrite');
      const store = tx.objectStore(this.storeName);
      store.put(record);
      tx.oncomplete = () => resolve();
      tx.onabort = () => reject(new Error('Transaction aborted during updateMeta'));
      tx.onerror = () => reject(tx.error);
    });
  }

  async delete(id: string): Promise<void> {
    const db = await this.getDb();
    await new Promise<void>((resolve, reject) => {
      const tx = db.transaction(this.storeName, 'readwrite');
      const store = tx.objectStore(this.storeName);
      store.delete(id);
      tx.oncomplete = () => resolve();
      tx.onabort = () => reject(new Error('Transaction aborted during delete'));
      tx.onerror = () => reject(tx.error);
    });
  }

  async batchDelete(ids: string[]): Promise<void> {
    const db = await this.getDb();
    await new Promise<void>((resolve, reject) => {
      const tx = db.transaction(this.storeName, 'readwrite');
      const store = tx.objectStore(this.storeName);
      for (const id of ids) {
        store.delete(id);
      }
      tx.oncomplete = () => resolve();
      tx.onabort = () => reject(new Error('Transaction aborted during batchDelete'));
      tx.onerror = () => reject(tx.error);
    });
  }

  private generateId(): string {
    const randomBytes = crypto.getRandomValues(new Uint8Array(8));
    const randomHex = Array.from(randomBytes)
      .map((b) => b.toString(16).padStart(2, '0'))
      .join('');
    return `${Date.now().toString(16)}-${randomHex}`;
  }
}
