export class VaultIntegrityException extends Error {
  constructor(message = 'VaultIntegrityException: Ciphertext or authentication tag is invalid or tampered with.') {
    super(message);
    this.name = 'VaultIntegrityException';
  }
}

export interface SealedVaultData {
  cipherText: Uint8Array;
  nonce: Uint8Array;
  mac: Uint8Array;
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
}
