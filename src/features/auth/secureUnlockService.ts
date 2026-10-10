import { SecretStore, LocalSecretStore } from '../../core/storage/secretStore';
import { PinHasher } from './pinHasher';

export class InvalidPinException extends Error {
  constructor(message = 'PIN must be between 4 and 12 digits.') {
    super(message);
    this.name = 'InvalidPinException';
  }
}

export interface VerifyResult {
  success: boolean;
  isDecoy: boolean;
}

export class SecureUnlockService {
  private static VERIFIER_KEY = 'pin_verifier_v1';
  private static DECOY_KEY = 'pin_decoy_verifier_v1';
  private store: SecretStore;
  private hasher: PinHasher;

  constructor(store: SecretStore = new LocalSecretStore(), hasher: PinHasher = new PinHasher()) {
    this.store = store;
    this.hasher = hasher;
  }

  isValidPin(pin: string): boolean {
    return /^\d{4,12}$/.test(pin);
  }

  async isConfigured(): Promise<boolean> {
    const raw = await this.store.read(SecureUnlockService.VERIFIER_KEY);
    return raw !== null;
  }

  async hasDecoy(): Promise<boolean> {
    const raw = await this.store.read(SecureUnlockService.DECOY_KEY);
    return raw !== null;
  }

  async configure(pin: string): Promise<void> {
    if (!this.isValidPin(pin)) {
      throw new InvalidPinException();
    }
    const verifier = await this.hasher.create(pin);
    await this.store.write(SecureUnlockService.VERIFIER_KEY, JSON.stringify(verifier));
  }

  async configureDecoy(decoyPin: string): Promise<void> {
    if (!this.isValidPin(decoyPin)) {
      throw new InvalidPinException();
    }
    const verifier = await this.hasher.create(decoyPin);
    await this.store.write(SecureUnlockService.DECOY_KEY, JSON.stringify(verifier));
  }

  async verify(candidate: string): Promise<boolean> {
    const res = await this.verifyFull(candidate);
    return res.success;
  }

  async verifyFull(candidate: string): Promise<VerifyResult> {
    if (!this.isValidPin(candidate)) {
      return { success: false, isDecoy: false };
    }

    // Check Decoy PIN first if configured
    const decoyRaw = await this.store.read(SecureUnlockService.DECOY_KEY);
    if (decoyRaw) {
      try {
        const decoyVerifier = JSON.parse(decoyRaw);
        const matchesDecoy = await this.hasher.verify(candidate, decoyVerifier);
        if (matchesDecoy) {
          return { success: true, isDecoy: true };
        }
      } catch {}
    }

    // Check Primary PIN
    const raw = await this.store.read(SecureUnlockService.VERIFIER_KEY);
    if (!raw) return { success: false, isDecoy: false };

    try {
      const verifier = JSON.parse(raw);
      if (!verifier.salt || !verifier.hash || !verifier.iterations) {
        return { success: false, isDecoy: false };
      }
      const matches = await this.hasher.verify(candidate, verifier);
      return { success: matches, isDecoy: false };
    } catch {
      return { success: false, isDecoy: false };
    }
  }

  async reset(): Promise<void> {
    await this.store.delete(SecureUnlockService.VERIFIER_KEY);
    await this.store.delete(SecureUnlockService.DECOY_KEY);
  }

  async resetDecoy(): Promise<void> {
    await this.store.delete(SecureUnlockService.DECOY_KEY);
  }
}
