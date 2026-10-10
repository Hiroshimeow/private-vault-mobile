import { VaultCrypto, SealedVaultData } from '../../core/crypto/vaultCrypto';
import { SecretStore, LocalSecretStore } from '../../core/storage/secretStore';
import { VaultItem, VaultItemKind } from '../../types';

export class MissingVaultKeyException extends Error {
  constructor(message = 'Vault master key is missing.') {
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

export class VaultKeyStore {
  private static STORAGE_KEY = 'vault_master_key_v1';
  private store: SecretStore;
  private crypto: VaultCrypto;

  constructor(store: SecretStore = new LocalSecretStore(), crypto: VaultCrypto = new VaultCrypto()) {
    this.store = store;
    this.crypto = crypto;
  }

  async getOrCreate(): Promise<CryptoKey> {
    const existing = await this.read();
    if (existing) return existing;

    const newKey = await this.crypto.newKey();
    const rawBytes = await this.crypto.exportKey(newKey);
    const b64 = this.bytesToBase64(rawBytes);
    await this.store.write(VaultKeyStore.STORAGE_KEY, b64);
    return newKey;
  }

  async read(): Promise<CryptoKey | null> {
    const raw = await this.store.read(VaultKeyStore.STORAGE_KEY);
    if (!raw) return null;
    try {
      const bytes = this.base64ToBytes(raw);
      return await this.crypto.importKey(bytes);
    } catch {
      throw new MissingVaultKeyException();
    }
  }

  private bytesToBase64(bytes: Uint8Array): string {
    let binary = '';
    for (let i = 0; i < bytes.byteLength; i++) {
      binary += String.fromCharCode(bytes[i]);
    }
    return btoa(binary);
  }

  private base64ToBytes(b64: string): Uint8Array {
    const binary = atob(b64);
    const bytes = new Uint8Array(binary.length);
    for (let i = 0; i < binary.length; i++) {
      bytes[i] = binary.charCodeAt(i);
    }
    return bytes;
  }
}

export class LocalVaultRepository {
  private keyStore: VaultKeyStore;
  private crypto: VaultCrypto;
  private dbName = 'private_vault_db_v1';
  private storeName = 'encrypted_items';
  private dbPromise: Promise<IDBDatabase> | null = null;

  constructor(keyStore?: VaultKeyStore, crypto?: VaultCrypto) {
    this.crypto = crypto ?? new VaultCrypto();
    this.keyStore = keyStore ?? new VaultKeyStore(new LocalSecretStore(), this.crypto);
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

  async addBytes(
    bytes: Uint8Array,
    options: {
      kind: VaultItemKind;
      name?: string;
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

    const key = await this.keyStore.getOrCreate();
    const id = this.generateId();
    const createdAt = new Date().toISOString();

    const sealedPayload = await this.crypto.encrypt(bytes, key);

    const metaClear = new TextEncoder().encode(
      JSON.stringify({
        id,
        kind: options.kind,
        name: options.name || `item-${id.slice(0, 8)}`,
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
      nonce: this.bytesToBase64(sealedPayload.nonce),
      mac: this.bytesToBase64(sealedPayload.mac),
      cipherText: this.bytesToBase64(sealedPayload.cipherText),
      metaNonce: this.bytesToBase64(sealedMeta.nonce),
      metaMac: this.bytesToBase64(sealedMeta.mac),
      metaCipherText: this.bytesToBase64(sealedMeta.cipherText),
      createdAt,
      size: bytes.byteLength,
    };

    const db = await this.getDb();
    await new Promise<void>((resolve, reject) => {
      const tx = db.transaction(this.storeName, 'readwrite');
      const store = tx.objectStore(this.storeName);
      const req = store.put(record);
      req.onsuccess = () => resolve();
      req.onerror = () => reject(req.error);
    });

    return {
      id,
      kind: options.kind,
      name: options.name,
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
  ): Promise<{ bytes: Uint8Array; kind: VaultItemKind; name: string; createdAt: string }> {
    const key = await this.requiredKey();
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
      nonce: this.base64ToBytes(record.metaNonce),
      mac: this.base64ToBytes(record.metaMac),
      cipherText: this.base64ToBytes(record.metaCipherText),
    };
    const metaBytes = await this.crypto.decrypt(metaSealed, key);
    const meta = JSON.parse(new TextDecoder().decode(metaBytes));

    const payloadSealed: SealedVaultData = {
      nonce: this.base64ToBytes(record.nonce),
      mac: this.base64ToBytes(record.mac),
      cipherText: this.base64ToBytes(record.cipherText),
    };
    const payloadBytes = await this.crypto.decrypt(payloadSealed, key);

    return {
      bytes: payloadBytes,
      kind: meta.kind,
      name: meta.name || `item-${id.slice(0, 8)}`,
      createdAt: meta.createdAt,
    };
  }

  async list(): Promise<VaultItem[]> {
    const key = await this.requiredKey();
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
          nonce: this.base64ToBytes(record.metaNonce),
          mac: this.base64ToBytes(record.metaMac),
          cipherText: this.base64ToBytes(record.metaCipherText),
        };
        const metaBytes = await this.crypto.decrypt(metaSealed, key);
        const meta = JSON.parse(new TextDecoder().decode(metaBytes));
        items.push({
          id: record.id,
          kind: meta.kind || 'unknown',
          name: meta.name,
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

  async updateMeta(id: string, updates: Partial<VaultItem>): Promise<void> {
    const key = await this.requiredKey();
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
      nonce: this.base64ToBytes(record.metaNonce),
      mac: this.base64ToBytes(record.metaMac),
      cipherText: this.base64ToBytes(record.metaCipherText),
    };
    const metaBytes = await this.crypto.decrypt(metaSealed, key);
    const meta = JSON.parse(new TextDecoder().decode(metaBytes));

    const updatedMeta = { ...meta, ...updates };
    const metaClear = new TextEncoder().encode(JSON.stringify(updatedMeta));
    const sealedMeta = await this.crypto.encrypt(metaClear, key);

    record.metaNonce = this.bytesToBase64(sealedMeta.nonce);
    record.metaMac = this.bytesToBase64(sealedMeta.mac);
    record.metaCipherText = this.bytesToBase64(sealedMeta.cipherText);

    await new Promise<void>((resolve, reject) => {
      const tx = db.transaction(this.storeName, 'readwrite');
      const store = tx.objectStore(this.storeName);
      const req = store.put(record);
      req.onsuccess = () => resolve();
      req.onerror = () => reject(req.error);
    });
  }

  async delete(id: string): Promise<void> {
    const db = await this.getDb();
    await new Promise<void>((resolve, reject) => {
      const tx = db.transaction(this.storeName, 'readwrite');
      const store = tx.objectStore(this.storeName);
      const req = store.delete(id);
      req.onsuccess = () => resolve();
      req.onerror = () => reject(req.error);
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
      tx.onerror = () => reject(tx.error);
    });
  }

  private async requiredKey(): Promise<CryptoKey> {
    const key = await this.keyStore.read();
    if (!key) throw new MissingVaultKeyException();
    return key;
  }

  private generateId(): string {
    const randomBytes = crypto.getRandomValues(new Uint8Array(8));
    const randomHex = Array.from(randomBytes)
      .map((b) => b.toString(16).padStart(2, '0'))
      .join('');
    return `${Date.now().toString(16)}-${randomHex}`;
  }

  private bytesToBase64(bytes: Uint8Array): string {
    let binary = '';
    for (let i = 0; i < bytes.byteLength; i++) {
      binary += String.fromCharCode(bytes[i]);
    }
    return btoa(binary);
  }

  private base64ToBytes(b64: string): Uint8Array {
    const binary = atob(b64);
    const bytes = new Uint8Array(binary.length);
    for (let i = 0; i < binary.length; i++) {
      bytes[i] = binary.charCodeAt(i);
    }
    return bytes;
  }
}
