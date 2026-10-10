import { SecretStore, LocalSecretStore } from '../../core/storage/secretStore';
import { PinHasher } from './pinHasher';
import { VaultKeyStore } from '../vault/vaultRepository';

export class InvalidPinException extends Error {
  constructor(message = 'PIN phải có độ dài từ 4 đến 12 chữ số.') {
    super(message);
    this.name = 'InvalidPinException';
  }
}

export interface VerifyResult {
  success: boolean;
  isDecoy: boolean;
  lockoutSeconds?: number;
  remainingAttempts?: number;
}

export class SecureUnlockService {
  private static VERIFIER_KEY = 'pin_verifier_v1';
  private static DECOY_KEY = 'pin_decoy_verifier_v1';
  private static LOCKOUT_KEY = 'auth_lockout_state_v1';

  private store: SecretStore;
  private hasher: PinHasher;
  private keyStore: VaultKeyStore;

  constructor(
    store: SecretStore = new LocalSecretStore(),
    hasher: PinHasher = new PinHasher(),
    keyStore?: VaultKeyStore
  ) {
    this.store = store;
    this.hasher = hasher;
    this.keyStore = keyStore ?? new VaultKeyStore(store);
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

  async getLockoutStatus(): Promise<{ isLocked: boolean; remainingSeconds: number }> {
    try {
      const raw = await this.store.read(SecureUnlockService.LOCKOUT_KEY);
      if (!raw) return { isLocked: false, remainingSeconds: 0 };
      const data = JSON.parse(raw);
      const now = Date.now();
      if (data.lockedUntil && data.lockedUntil > now) {
        return {
          isLocked: true,
          remainingSeconds: Math.ceil((data.lockedUntil - now) / 1000),
        };
      }
      return { isLocked: false, remainingSeconds: 0 };
    } catch {
      return { isLocked: false, remainingSeconds: 0 };
    }
  }

  private async recordFailedAttempt(): Promise<{ lockedUntil: number | null; remainingSeconds: number }> {
    let attempts = 0;
    try {
      const raw = await this.store.read(SecureUnlockService.LOCKOUT_KEY);
      if (raw) {
        const data = JSON.parse(raw);
        attempts = data.attempts || 0;
      }
    } catch {}

    attempts += 1;
    let lockoutDurationMs = 0;
    if (attempts >= 5) {
      lockoutDurationMs = 60 * 1000; // 60s lockout
    } else if (attempts >= 3) {
      lockoutDurationMs = 30 * 1000; // 30s lockout
    }

    const lockedUntil = lockoutDurationMs > 0 ? Date.now() + lockoutDurationMs : null;
    await this.store.write(
      SecureUnlockService.LOCKOUT_KEY,
      JSON.stringify({ attempts, lockedUntil })
    );

    return {
      lockedUntil,
      remainingSeconds: Math.ceil(lockoutDurationMs / 1000),
    };
  }

  private async clearLockout(): Promise<void> {
    try {
      await this.store.delete(SecureUnlockService.LOCKOUT_KEY);
    } catch {}
  }

  async configure(pin: string): Promise<void> {
    if (!this.isValidPin(pin)) {
      throw new InvalidPinException();
    }
    const verifier = await this.hasher.create(pin);
    await this.store.write(SecureUnlockService.VERIFIER_KEY, JSON.stringify(verifier));

    // Provision encrypted master key with KEK derived from PIN
    await this.keyStore.provision(pin);
    await this.clearLockout();
  }

  async configureDecoy(decoyPin: string): Promise<void> {
    if (!this.isValidPin(decoyPin)) {
      throw new InvalidPinException();
    }
    const verifier = await this.hasher.create(decoyPin);
    await this.store.write(SecureUnlockService.DECOY_KEY, JSON.stringify(verifier));
  }

  /**
   * Verifies PIN and unlocks master key into active session if valid.
   */
  async unlock(candidate: string): Promise<VerifyResult> {
    const lockout = await this.getLockoutStatus();
    if (lockout.isLocked) {
      return {
        success: false,
        isDecoy: false,
        lockoutSeconds: lockout.remainingSeconds,
      };
    }

    if (!this.isValidPin(candidate)) {
      return { success: false, isDecoy: false };
    }

    // 1. Check Decoy PIN first if configured
    const decoyRaw = await this.store.read(SecureUnlockService.DECOY_KEY);
    if (decoyRaw) {
      try {
        const decoyVerifier = JSON.parse(decoyRaw);
        const matchesDecoy = await this.hasher.verify(candidate, decoyVerifier);
        if (matchesDecoy) {
          // A07 fix: Decoy NEVER unlocks real vault master key!
          await this.clearLockout();
          return { success: true, isDecoy: true };
        }
      } catch {}
    }

    // 2. Check Primary PIN
    const raw = await this.store.read(SecureUnlockService.VERIFIER_KEY);
    if (!raw) return { success: false, isDecoy: false };

    try {
      const verifier = JSON.parse(raw);
      if (!verifier.salt || !verifier.hash || !verifier.iterations) {
        return { success: false, isDecoy: false };
      }
      const matches = await this.hasher.verify(candidate, verifier);
      if (matches) {
        // Unlock master key and start active session
        await this.keyStore.unlock(candidate);
        await this.clearLockout();
        return { success: true, isDecoy: false };
      }
    } catch {
      // verification error
    }

    // Record failed attempt and compute lockout
    const failedInfo = await this.recordFailedAttempt();
    return {
      success: false,
      isDecoy: false,
      lockoutSeconds: failedInfo.remainingSeconds,
    };
  }

  async verify(candidate: string): Promise<boolean> {
    const res = await this.unlock(candidate);
    return res.success && !res.isDecoy;
  }

  async reset(): Promise<void> {
    await this.store.delete(SecureUnlockService.VERIFIER_KEY);
    await this.store.delete(SecureUnlockService.DECOY_KEY);
    await this.clearLockout();
  }

  async resetDecoy(): Promise<void> {
    await this.store.delete(SecureUnlockService.DECOY_KEY);
  }
}
