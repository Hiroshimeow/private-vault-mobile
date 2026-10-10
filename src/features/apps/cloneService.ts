import { CloneApp, CloneProfileState } from '../../types';
import { nativeCloneBridge } from './nativeCloneBridge';

export const BUILTIN_VAULT_APPS: CloneApp[] = [
  {
    id: 'gallery',
    name: 'Bộ sưu tập Bảo mật',
    packageName: 'io.privatevault.gallery',
    category: 'system',
    status: 'cloned',
    iconColor: '#00a389',
    iconType: 'gallery',
    isBuiltinSecureApp: true,
  },
  {
    id: 'camera',
    name: 'Máy ảnh Bảo mật',
    packageName: 'io.privatevault.camera',
    category: 'system',
    status: 'cloned',
    iconColor: '#e11d48',
    iconType: 'camera',
    isBuiltinSecureApp: true,
  },
  {
    id: 'notes',
    name: 'Ghi chú Bảo mật',
    packageName: 'io.privatevault.notes',
    category: 'system',
    status: 'cloned',
    iconColor: '#f59e0b',
    iconType: 'notes',
    isBuiltinSecureApp: true,
  },
  {
    id: 'files',
    name: 'File Bảo mật',
    packageName: 'io.privatevault.files',
    category: 'system',
    status: 'cloned',
    iconColor: '#d97706',
    iconType: 'files',
    isBuiltinSecureApp: true,
  },
  {
    id: 'browser',
    name: 'Trình duyệt Ẩn danh',
    packageName: 'io.privatevault.browser',
    category: 'system',
    status: 'cloned',
    iconColor: '#3b82f6',
    iconType: 'browser',
    isBuiltinSecureApp: true,
  },
  {
    id: 'audio',
    name: 'Ghi âm Bảo mật',
    packageName: 'io.privatevault.audio',
    category: 'system',
    status: 'cloned',
    iconColor: '#8b5cf6',
    iconType: 'audio',
    isBuiltinSecureApp: true,
  },
];

export class CloneService {
  private static APPS_KEY = 'pv_native_clone_apps_v2';

  async getProfileState(): Promise<CloneProfileState> {
    const bridgeState = await nativeCloneBridge.getProfileStatus();
    const shizuku = await nativeCloneBridge.isShizukuAvailable();

    return {
      engine: 'shizuku_clone',
      isProvisioned: bridgeState.profileExists,
      isPaused: bridgeState.isPaused,
      profileUserId: bridgeState.profileUserId,
      shizukuAvailable: shizuku.available && shizuku.authorized,
      dpcAdminGranted: false, // DPC/Work profile is deprecated in favor of profile.CLONE
    };
  }

  loadApps(): CloneApp[] {
    try {
      const raw = localStorage.getItem(CloneService.APPS_KEY);
      if (raw) {
        const parsed = JSON.parse(raw);
        if (Array.isArray(parsed) && parsed.length > 0) {
          return parsed;
        }
      }
    } catch {}
    return [...BUILTIN_VAULT_APPS];
  }

  saveApps(apps: CloneApp[]): void {
    try {
      localStorage.setItem(CloneService.APPS_KEY, JSON.stringify(apps));
    } catch (err) {
      console.error('Failed to save clone apps list:', err);
    }
  }

  async clonePackage(packageName: string, appName: string, profileUserId: number): Promise<CloneApp[]> {
    await nativeCloneBridge.clonePackage({ packageName, profileUserId });
    const current = this.loadApps();
    const existing = current.find((a) => a.packageName === packageName);

    let next: CloneApp[];
    if (existing) {
      next = current.map((a) =>
        a.packageName === packageName ? { ...a, status: 'cloned' as const } : a
      );
    } else {
      const newApp: CloneApp = {
        id: `clone-${Date.now()}`,
        name: appName,
        packageName,
        category: 'custom',
        status: 'cloned',
        iconColor: '#00a389',
        lastLaunchedAt: new Date().toISOString(),
      };
      next = [...current, newApp];
    }
    this.saveApps(next);
    return next;
  }

  async removeClone(app: CloneApp, profileUserId: number | null): Promise<CloneApp[]> {
    if (profileUserId && !app.isBuiltinSecureApp) {
      await nativeCloneBridge.removePackage({ packageName: app.packageName, profileUserId });
    }
    const current = this.loadApps();
    const next = current.filter((a) => a.id !== app.id);
    this.saveApps(next);
    return next;
  }

  async launchApp(app: CloneApp, profileUserId: number | null): Promise<boolean> {
    if (app.isBuiltinSecureApp) {
      return true;
    }
    if (!profileUserId) {
      throw new Error('Chưa thiết lập hồ sơ clone profile.CLONE trên hệ điều hành Android.');
    }
    const res = await nativeCloneBridge.launchPackageInProfile({
      packageName: app.packageName,
      profileUserId,
    });
    return res.success;
  }
}
