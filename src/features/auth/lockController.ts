import { VaultSessionManager } from '../vault/vaultSession';

type Listener = () => void;

export class LockController {
  private _isLocked = true; // Locked by default on launch
  private _backgroundTimer: ReturnType<typeof setTimeout> | null = null;
  private _confidentialityBoundary: (() => void) | null = null;
  private _listeners: Set<Listener> = new Set();
  public backgroundLock = true;
  private _isSuspended = false;
  private _lockDisabled = false;

  get isLocked(): boolean {
    return this._isLocked;
  }

  get isSuspended(): boolean {
    return this._isSuspended;
  }

  suspendLock(suspended = true): void {
    this._isSuspended = suspended;
    if (suspended && this._backgroundTimer) {
      clearTimeout(this._backgroundTimer);
      this._backgroundTimer = null;
    }
  }

  get isLockDisabled(): boolean {
    return this._lockDisabled;
  }

  setLockDisabled(disabled: boolean): void {
    this._lockDisabled = disabled;
    if (disabled && this._isLocked) {
      this._isLocked = false;
      this.notify();
    }
  }

  subscribe(listener: Listener): () => void {
    this._listeners.add(listener);
    return () => {
      this._listeners.delete(listener);
    };
  }

  private notify(): void {
    for (const listener of this._listeners) {
      listener();
    }
  }

  attachConfidentialityBoundary(callback: () => void): void {
    this._confidentialityBoundary = callback;
  }

  detachConfidentialityBoundary(callback: () => void): void {
    if (this._confidentialityBoundary === callback) {
      this._confidentialityBoundary = null;
    }
  }

  unlock(): void {
    if (this._backgroundTimer) {
      clearTimeout(this._backgroundTimer);
      this._backgroundTimer = null;
    }
    if (!this._isLocked) return;
    this._isLocked = false;
    this.notify();
  }

  lock(force = false): void {
    if (!force && this._lockDisabled) return;
    if (this._backgroundTimer) {
      clearTimeout(this._backgroundTimer);
      this._backgroundTimer = null;
    }
    // Revoke cryptographic session and in-memory master key
    VaultSessionManager.getInstance().revoke();
    this._confidentialityBoundary?.();
    if (this._isLocked) return;
    this._isLocked = true;
    this.notify();
  }

  panic(): void {
    this.lock(true);
  }

  onBackground(delayMs = 0): void {
    if (this._lockDisabled || this._isSuspended || !this.backgroundLock || this._isLocked) return;
    if (this._backgroundTimer) {
      clearTimeout(this._backgroundTimer);
    }

    if (delayMs <= 0) {
      this.lock();
      return;
    }

    this._backgroundTimer = setTimeout(() => {
      this.lock();
    }, delayMs);
  }

  onForeground(): void {
    if (this._backgroundTimer) {
      clearTimeout(this._backgroundTimer);
      this._backgroundTimer = null;
    }
  }

  dispose(): void {
    if (this._backgroundTimer) {
      clearTimeout(this._backgroundTimer);
      this._backgroundTimer = null;
    }
    this._listeners.clear();
  }
}
