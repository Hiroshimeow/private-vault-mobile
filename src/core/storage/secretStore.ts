export class StorageException extends Error {
  constructor(message = 'Storage operation failed', options?: ErrorOptions) {
    super(message, options);
    this.name = 'StorageException';
  }
}

export interface SecretStore {
  read(key: string): Promise<string | null>;
  write(key: string, value: string): Promise<void>;
  delete(key: string): Promise<void>;
}

export class LocalSecretStore implements SecretStore {
  private prefix = 'pv_secret_';

  async read(key: string): Promise<string | null> {
    try {
      const val = localStorage.getItem(this.prefix + key);
      return val;
    } catch (err) {
      throw new StorageException(`Failed to read from secret store: ${key}`, { cause: err });
    }
  }

  async write(key: string, value: string): Promise<void> {
    try {
      localStorage.setItem(this.prefix + key, value);
    } catch (err) {
      throw new StorageException(`Failed to write to secret store: ${key}`, { cause: err });
    }
  }

  async delete(key: string): Promise<void> {
    try {
      localStorage.removeItem(this.prefix + key);
    } catch (err) {
      throw new StorageException(`Failed to remove from secret store: ${key}`, { cause: err });
    }
  }
}
