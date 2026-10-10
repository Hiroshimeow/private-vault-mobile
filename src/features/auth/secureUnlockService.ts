import { SecretStore, LocalSecretStore } from '../../core/storage/secretStore';
import { PinHasher } from './pinHasher';

export class InvalidPinException extends Error {
  constructor(message = 'PIN must be between 6 and 12 digits.') {
    super(message);
    this.name = 'InvalidPinException';
  }
}

export class SecureUnlockService {
  private static VERIFIER_KEY = 'pin_verifier_v1';
  private store: SecretStore;
  private hasher: PinHasher;

  constructor(store: SecretStore = new LocalSecretStore(), hasher: PinHasher = new PinHasher()) {
    this.store = store;
    this.hasher = hasher;
  }

  isValidPin(pin: string): boolean {
    return /^\d{6,12}$/.test(pin);
  }

  async isConfigured(): Promise<boolean> {
    const raw = await this.store.read(SecureUnlockService.VERIFIER_KEY);
    return raw !== null;
  }

  async configure(pin: string): Promise<void> {
    if (!this.isValidPin(pin)) {
      throw new InvalidPinException();
    }
    const verifier = await this.hasher.create(pin);
    await this.store.write(SecureUnlockService.VERIFIER_KEY, JSON.stringify(verifier));
  }

  async verify(candidate: string): Promise<boolean> {
    if (!this.isValidPin(candidate)) {
      return false;
    }
    const raw = await this.store.read(SecureUnlockService.VERIFIER_KEY);
    if (!raw) return false;

    try {
      const verifier = JSON.parse(raw);
      if (!verifier.salt || !verifier.hash || !verifier.iterations) {
        return false;
      }
      return await this.hasher.verify(candidate, verifier);
    } catch {
      return false;
    }
  }

  async reset(): Promise<void> {
    await this.store.delete(SecureUnlockService.VERIFIER_KEY);
  }
}
