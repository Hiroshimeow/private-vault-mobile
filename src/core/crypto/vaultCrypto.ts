export class VaultIntegrityException extends Error {
  constructor(message = 'VaultIntegrityException: Ciphertext or authentication tag is invalid or tampered with.') {
    super(message);
    this.name = 'VaultIntegrityException';
  }
}

export class VaultLockedException extends Error {
  constructor(message = 'VaultLockedException: Vault is currently locked. Decryption or encryption session is revoked.') {
    super(message);
    this.name = 'VaultLockedException';
  }
}

export interface SealedVaultData {
  cipherText: Uint8Array;
  nonce: Uint8Array;
  mac: Uint8Array;
}

export interface SerializedSealedData {
  cipherText: string; // base64
  nonce: string; // base64
  mac: string; // base64
}

export class VaultCrypto {
  /**
   * Generates a new 256-bit AES-GCM CryptoKey.
   */
  async newKey(): Promise<CryptoKey> {
    return await crypto.subtle.generateKey(
      { name: 'AES-GCM', length: 256 },
      true,
      ['encrypt', 'decrypt']
    );
  }

  /**
   * Imports a raw 32-byte key into a CryptoKey.
   */
  async importKey(rawBytes: Uint8Array): Promise<CryptoKey> {
    return await crypto.subtle.importKey(
      'raw',
      rawBytes,
      { name: 'AES-GCM', length: 256 },
      true,
      ['encrypt', 'decrypt']
    );
  }

  /**
   * Exports a CryptoKey to raw 32-byte Uint8Array.
   */
  async exportKey(key: CryptoKey): Promise<Uint8Array> {
    const raw = await crypto.subtle.exportKey('raw', key);
    return new Uint8Array(raw);
  }

  /**
   * Derives an AES-GCM Key-Encryption-Key (KEK) from a PIN using PBKDF2.
   */
  async deriveKek(pin: string, salt: Uint8Array, iterations = 100000): Promise<CryptoKey> {
    const enc = new TextEncoder();
    const pinKeyMaterial = await crypto.subtle.importKey(
      'raw',
      enc.encode(pin),
      { name: 'PBKDF2' },
      false,
      ['deriveKey']
    );

    return await crypto.subtle.deriveKey(
      {
        name: 'PBKDF2',
        salt,
        iterations,
        hash: 'SHA-256',
      },
      pinKeyMaterial,
      { name: 'AES-GCM', length: 256 },
      false,
      ['encrypt', 'decrypt']
    );
  }

  /**
   * Wraps a master key by encrypting its raw export with a KEK.
   */
  async wrapKey(masterKey: CryptoKey, kek: CryptoKey): Promise<SealedVaultData> {
    const rawBytes = await this.exportKey(masterKey);
    return await this.encrypt(rawBytes, kek);
  }

  /**
   * Unwraps a master key by decrypting with KEK and importing back to CryptoKey.
   */
  async unwrapKey(sealed: SealedVaultData, kek: CryptoKey): Promise<CryptoKey> {
    const rawBytes = await this.decrypt(sealed, kek);
    if (rawBytes.length !== 32) {
      throw new VaultIntegrityException('Unwrapped master key length is not 32 bytes');
    }
    return await this.importKey(rawBytes);
  }

  /**
   * Encrypts plaintext bytes using AES-GCM with a random 12-byte nonce.
   */
  async encrypt(clearText: Uint8Array, key: CryptoKey): Promise<SealedVaultData> {
    const nonce = crypto.getRandomValues(new Uint8Array(12));
    const encryptedBuffer = await crypto.subtle.encrypt(
      {
        name: 'AES-GCM',
        iv: nonce,
        tagLength: 128,
      },
      key,
      clearText
    );

    const fullResult = new Uint8Array(encryptedBuffer);
    const tagLength = 16;
    const cipherText = fullResult.slice(0, fullResult.length - tagLength);
    const mac = fullResult.slice(fullResult.length - tagLength);

    return {
      cipherText,
      nonce,
      mac,
    };
  }

  /**
   * Decrypts sealed data using AES-GCM. Reconstructs cipherText + tag and verifies MAC.
   */
  async decrypt(sealed: SealedVaultData, key: CryptoKey): Promise<Uint8Array> {
    try {
      const combined = new Uint8Array(sealed.cipherText.length + sealed.mac.length);
      combined.set(sealed.cipherText, 0);
      combined.set(sealed.mac, sealed.cipherText.length);

      const decryptedBuffer = await crypto.subtle.decrypt(
        {
          name: 'AES-GCM',
          iv: sealed.nonce,
          tagLength: 128,
        },
        key,
        combined
      );

      return new Uint8Array(decryptedBuffer);
    } catch {
      throw new VaultIntegrityException();
    }
  }

  bytesToBase64(bytes: Uint8Array): string {
    let binary = '';
    for (let i = 0; i < bytes.byteLength; i++) {
      binary += String.fromCharCode(bytes[i]);
    }
    return btoa(binary);
  }

  base64ToBytes(b64: string): Uint8Array {
    const binary = atob(b64);
    const bytes = new Uint8Array(binary.length);
    for (let i = 0; i < binary.length; i++) {
      bytes[i] = binary.charCodeAt(i);
    }
    return bytes;
  }
}
