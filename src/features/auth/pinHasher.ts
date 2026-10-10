export interface PinVerifier {
  salt: string;
  hash: string;
  iterations: number;
}

export class PinHasher {
  private iterations: number;

  constructor(iterations = 100000) {
    this.iterations = iterations;
  }

  async create(pin: string): Promise<PinVerifier> {
    const saltBytes = crypto.getRandomValues(new Uint8Array(16));
    const salt = this.bytesToHex(saltBytes);
    const hash = await this.hashPin(pin, saltBytes, this.iterations);
    return {
      salt,
      hash,
      iterations: this.iterations,
    };
  }

  async verify(pin: string, verifier: PinVerifier): Promise<boolean> {
    const saltBytes = this.hexToBytes(verifier.salt);
    const candidateHash = await this.hashPin(pin, saltBytes, verifier.iterations);
    return candidateHash === verifier.hash;
  }

  private async hashPin(pin: string, salt: Uint8Array, iterations: number): Promise<string> {
    const enc = new TextEncoder();
    const pinKey = await crypto.subtle.importKey(
      'raw',
      enc.encode(pin),
      { name: 'PBKDF2' },
      false,
      ['deriveBits']
    );

    const derivedBits = await crypto.subtle.deriveBits(
      {
        name: 'PBKDF2',
        salt,
        iterations,
        hash: 'SHA-256',
      },
      pinKey,
      256
    );

    return this.bytesToHex(new Uint8Array(derivedBits));
  }

  private bytesToHex(bytes: Uint8Array): string {
    return Array.from(bytes)
      .map((b) => b.toString(16).padStart(2, '0'))
      .join('');
  }

  private hexToBytes(hex: string): Uint8Array {
    const bytes = new Uint8Array(hex.length / 2);
    for (let i = 0; i < bytes.length; i++) {
      bytes[i] = parseInt(hex.substring(i * 2, i * 2 + 2), 16);
    }
    return bytes;
  }
}
