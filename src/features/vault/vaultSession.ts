import { VaultLockedException } from '../../core/crypto/vaultCrypto';

export class ActiveVaultSession {
  public readonly id: string;
  public readonly generation: number;
  private _key: CryptoKey | null;
  private _isRevoked = false;

  constructor(key: CryptoKey, generation: number) {
    this.id = `sess-${Date.now()}-${Math.random().toString(36).slice(2, 9)}`;
    this.generation = generation;
    this._key = key;
  }

  get isRevoked(): boolean {
    return this._isRevoked;
  }

  getKey(): CryptoKey {
    if (this._isRevoked || !this._key) {
      throw new VaultLockedException('Phiên bảo mật đã bị khóa. Quyền giải mã bị thu hồi.');
    }
    return this._key;
  }

  revoke(): void {
    this._isRevoked = true;
    this._key = null;
  }
}

export class VaultSessionManager {
  private static instance: VaultSessionManager;
  private _activeSession: ActiveVaultSession | null = null;
  private _generationCounter = 0;
  private _listeners: Set<() => void> = new Set();

  static getInstance(): VaultSessionManager {
    if (!VaultSessionManager.instance) {
      VaultSessionManager.instance = new VaultSessionManager();
    }
    return VaultSessionManager.instance;
  }

  getActiveSession(): ActiveVaultSession | null {
    if (this._activeSession?.isRevoked) {
      this._activeSession = null;
    }
    return this._activeSession;
  }

  get currentGeneration(): number {
    return this._generationCounter;
  }

  startSession(key: CryptoKey): ActiveVaultSession {
    if (this._activeSession) {
      this._activeSession.revoke();
    }
    this._generationCounter++;
    this._activeSession = new ActiveVaultSession(key, this._generationCounter);
    this.notify();
    return this._activeSession;
  }

  revoke(): void {
    if (this._activeSession) {
      this._activeSession.revoke();
      this._activeSession = null;
    }
    this._generationCounter++;
    this.notify();
  }

  subscribe(listener: () => void): () => void {
    this._listeners.add(listener);
    return () => {
      this._listeners.delete(listener);
    };
  }

  private notify(): void {
    for (const listener of this._listeners) {
      try {
        listener();
      } catch (err) {
        console.error('Session listener error:', err);
      }
    }
  }
}
