import { LocalVaultRepository } from './vaultRepository';

export interface BackupPackage {
  version: number;
  createdAt: string;
  itemCount: number;
  items: Array<{
    id: string;
    kind: string;
    name: string;
    createdAt: string;
    album?: string;
    isFavorite?: boolean;
    duration?: string;
    dataBase64: string;
  }>;
}

export class VaultBackupService {
  static async exportBackup(repository: LocalVaultRepository): Promise<Blob> {
    const items = await repository.list();
    const packagedItems = [];

    for (const item of items) {
      try {
        const raw = await repository.readBytes(item.id);
        let binary = '';
        const bytes = raw.bytes;
        for (let i = 0; i < bytes.byteLength; i++) {
          binary += String.fromCharCode(bytes[i]);
        }
        const dataBase64 = btoa(binary);

        packagedItems.push({
          id: item.id,
          kind: item.kind,
          name: item.name || raw.name,
          createdAt: item.createdAt,
          album: item.album,
          isFavorite: item.isFavorite,
          duration: item.duration,
          dataBase64,
        });
      } catch (err) {
        console.warn('Skipping item in backup:', item.id, err);
      }
    }

    const payload: BackupPackage = {
      version: 1,
      createdAt: new Date().toISOString(),
      itemCount: packagedItems.length,
      items: packagedItems,
    };

    const json = JSON.stringify(payload);
    return new Blob([json], { type: 'application/json' });
  }

  static async importBackup(file: File, repository: LocalVaultRepository): Promise<number> {
    const text = await file.text();
    const pkg: BackupPackage = JSON.parse(text);

    if (!pkg.items || !Array.isArray(pkg.items)) {
      throw new Error('Gói sao lưu không hợp lệ');
    }

    let imported = 0;
    for (const item of pkg.items) {
      try {
        const binary = atob(item.dataBase64);
        const bytes = new Uint8Array(binary.length);
        for (let i = 0; i < binary.length; i++) {
          bytes[i] = binary.charCodeAt(i);
        }

        await repository.addBytes(bytes, {
          kind: item.kind as any,
          name: item.name,
          album: item.album,
          isFavorite: item.isFavorite,
          duration: item.duration,
        });
        imported++;
      } catch (err) {
        console.error('Failed to restore item:', item.name, err);
      }
    }

    return imported;
  }
}
