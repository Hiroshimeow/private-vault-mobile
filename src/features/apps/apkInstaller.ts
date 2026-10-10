import { CloneApp } from '../../types';

export class InvalidApkException extends Error {
  constructor(message = 'Tệp tin không phải là APK Android hợp lệ.') {
    super(message);
    this.name = 'InvalidApkException';
  }
}

export interface ApkMetadata {
  fileName: string;
  fileSizeBytes: number;
  appName: string;
  packageName: string;
  versionName: string;
  sha256: string;
  hasManifest: boolean;
  hasDex: boolean;
  iconColor: string;
}

export class ApkParser {
  /**
   * Genuine binary APK archive parser.
   * Validates ZIP magic bytes and checks for AndroidManifest.xml and classes.dex.
   * Fails closed on invalid files (fixing A09 finding).
   */
  static async parseApkFile(file: File): Promise<ApkMetadata> {
    const buffer = await file.arrayBuffer();
    const bytes = new Uint8Array(buffer);

    // 1. Check ZIP magic number: PK\x03\x04 (0x50, 0x4B, 0x03, 0x04)
    if (
      bytes.length < 30 ||
      bytes[0] !== 0x50 ||
      bytes[1] !== 0x4b ||
      bytes[2] !== 0x03 ||
      bytes[3] !== 0x04
    ) {
      throw new InvalidApkException('Tệp tin không có định dạng nén ZIP/APK hợp lệ.');
    }

    // 2. Scan ZIP entries for AndroidManifest.xml and classes.dex
    let hasManifest = false;
    let hasDex = false;
    let offset = 0;
    const decoder = new TextDecoder('utf-8');

    while (offset + 30 <= bytes.length) {
      // Check for local file header signature 0x04034b50
      if (
        bytes[offset] !== 0x50 ||
        bytes[offset + 1] !== 0x4b ||
        bytes[offset + 2] !== 0x03 ||
        bytes[offset + 3] !== 0x04
      ) {
        break;
      }

      const compressedSize =
        bytes[offset + 18] |
        (bytes[offset + 19] << 8) |
        (bytes[offset + 20] << 16) |
        (bytes[offset + 21] << 24);
      const fileNameLength = bytes[offset + 26] | (bytes[offset + 27] << 8);
      const extraFieldLength = bytes[offset + 28] | (bytes[offset + 29] << 8);

      const fileNameStart = offset + 30;
      if (fileNameStart + fileNameLength <= bytes.length) {
        const fileNameBytes = bytes.subarray(fileNameStart, fileNameStart + fileNameLength);
        const fileName = decoder.decode(fileNameBytes);

        if (fileName === 'AndroidManifest.xml') {
          hasManifest = true;
        } else if (fileName === 'classes.dex') {
          hasDex = true;
        }
      }

      // Move to next entry
      offset += 30 + fileNameLength + extraFieldLength + compressedSize;
    }

    if (!hasManifest) {
      throw new InvalidApkException('Tệp APK không chứa tệp kê khai AndroidManifest.xml.');
    }

    // 3. Compute real SHA-256
    const sha256 = await this.calculateSha256(buffer);

    // Clean display name from file
    const cleanName = file.name.replace(/\.apk$/i, '');
    const cleanPackage = `package.${cleanName.toLowerCase().replace(/[^a-z0-9_.]/g, '')}`;

    return {
      fileName: file.name,
      fileSizeBytes: file.size,
      appName: cleanName,
      packageName: cleanPackage,
      versionName: 'Xác thực qua OS PackageInstaller',
      sha256,
      hasManifest,
      hasDex,
      iconColor: '#00a389',
    };
  }

  private static async calculateSha256(buffer: ArrayBuffer): Promise<string> {
    const digest = await crypto.subtle.digest('SHA-256', buffer);
    const hashArray = Array.from(new Uint8Array(digest));
    return hashArray.map((b) => b.toString(16).padStart(2, '0')).join('');
  }

  static createCloneAppFromApk(meta: ApkMetadata): CloneApp {
    return {
      id: `apk-${Date.now()}-${Math.random().toString(36).slice(2, 7)}`,
      name: meta.appName,
      packageName: meta.packageName,
      category: 'custom',
      status: 'uncloned', // Stored in Vault; requires OS PackageInstaller to be cloned
      iconColor: meta.iconColor,
      dataSizeBytes: meta.fileSizeBytes,
      lastLaunchedAt: new Date().toISOString(),
    };
  }
}
