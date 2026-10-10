// In-memory persistent cache for decrypted media thumbnails and blobs
// Avoids repeated AES-GCM decryption and re-allocation on tab switching or re-renders

class ThumbnailCache {
  private cache = new Map<string, string>();

  get(id: string): string | undefined {
    return this.cache.get(id);
  }

  set(id: string, url: string): void {
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
      } catch {
        // ignore
      }
      this.cache.delete(id);
    }
  }

  clear(): void {
    this.cache.forEach((url) => {
      try {
        URL.revokeObjectURL(url);
      } catch {
        // ignore
      }
    });
    this.cache.clear();
  }
}

export const thumbnailCache = new ThumbnailCache();
