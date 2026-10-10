import { VaultSessionManager } from '../vault/vaultSession';

/**
 * LRU bounded in-memory cache for decrypted thumbnails.
 * Bound to ActiveVaultSession: automatically revokes all Blob URLs on lock/panic.
 */
class ThumbnailCache {
  private cache = new Map<string, string>();
  private readonly maxEntries = 64;

  constructor() {
    // Subscribe to session manager: clear and revoke all Blob URLs on lock or panic
    VaultSessionManager.getInstance().subscribe(() => {
      this.clear();
    });
  }

  get(id: string): string | undefined {
    const url = this.cache.get(id);
    if (url) {
      // Re-insert to mark as recently used
      this.cache.delete(id);
      this.cache.set(id, url);
    }
    return url;
  }

  set(id: string, url: string): void {
    if (this.cache.has(id)) {
      const oldUrl = this.cache.get(id);
      if (oldUrl && oldUrl !== url) {
        try {
          URL.revokeObjectURL(oldUrl);
        } catch {}
      }
      this.cache.delete(id);
    } else if (this.cache.size >= this.maxEntries) {
      // Evict oldest entry (first item in Map)
      const oldestKey = this.cache.keys().next().value;
      if (oldestKey) {
        const oldestUrl = this.cache.get(oldestKey);
        if (oldestUrl) {
          try {
            URL.revokeObjectURL(oldestUrl);
          } catch {}
        }
        this.cache.delete(oldestKey);
      }
    }
    this.cache.set(id, url);
  }

  has(id: string): boolean {
    return this.cache.has(id);
  }

  remove(id: string): void {
    const url = this.cache.get(id);
    if (url) {
      try {
        URL.revokeObjectURL(url);
      } catch {}
      this.cache.delete(id);
    }
  }

  clear(): void {
    this.cache.forEach((url) => {
      try {
        URL.revokeObjectURL(url);
      } catch {}
    });
    this.cache.clear();
  }
}

export const thumbnailCache = new ThumbnailCache();
