/**
 * Portable Vault Backup Service.
 * STATUS: BLOCKED pending frozen byte format / Argon2id specification from canonical repository.
 * In accordance with audit finding A19: Unencrypted plaintext JSON/Base64 export MUST NOT be exposed
 * as a secure backup feature. Custom cryptographic backup formats must not be invented.
 */

export class BackupBlockedException extends Error {
  constructor(message = 'Tính năng Portable Vault Backup hiện đang tạm hoãn (BLOCKED) chờ đặc tả mã hóa Portable Vault V2 chuẩn.') {
    super(message);
    this.name = 'BackupBlockedException';
  }
}

export class VaultBackupService {
  static isAvailable(): boolean {
    return false; // Not exposed until frozen V2 format is integrated
  }

  static async exportBackup(): Promise<Blob> {
    throw new BackupBlockedException();
  }

  static async importBackup(): Promise<number> {
    throw new BackupBlockedException();
  }
}
