import { CloneApp, CloneProfileState, CloneEngineMode } from '../../types';

export const CATALOG_PRESETS: CloneApp[] = [
  // Built-in Secure Apps (Samsung One UI defaults)
  {
    id: 'gallery',
    name: 'Bộ sưu tập',
    packageName: 'com.sec.android.gallery3d',
    category: 'system',
    status: 'cloned',
    iconColor: '#00a389',
    iconType: 'gallery',
    isBuiltinSecureApp: true,
  },
  {
    id: 'camera',
    name: 'Máy ảnh',
    packageName: 'com.sec.android.app.camera',
    category: 'system',
    status: 'cloned',
    iconColor: '#e11d48',
    iconType: 'camera',
    isBuiltinSecureApp: true,
  },
  {
    id: 'notes',
    name: 'Samsung Notes',
    packageName: 'com.samsung.android.app.notes',
    category: 'system',
    status: 'cloned',
    iconColor: '#f59e0b',
    iconType: 'notes',
    isBuiltinSecureApp: true,
  },
  {
    id: 'browser',
    name: 'Internet',
    packageName: 'com.sec.android.app.sbrowser',
    category: 'system',
    status: 'cloned',
    iconColor: '#3b82f6',
    iconType: 'browser',
    isBuiltinSecureApp: true,
  },
  {
    id: 'files',
    name: 'File của bạn',
    packageName: 'com.sec.android.app.myfiles',
    category: 'system',
    status: 'cloned',
    iconColor: '#d97706',
    iconType: 'files',
    isBuiltinSecureApp: true,
  },
  // User Cloned Apps (Active)
  {
    id: 'zalo',
    name: 'Zalo',
    packageName: 'com.zing.zalo',
    category: 'messaging',
    status: 'cloned',
    iconColor: '#0068ff',
    lastLaunchedAt: new Date(Date.now() - 1800000).toISOString(),
    dataSizeBytes: 42 * 1024 * 1024,
    badgeCount: 2,
  },
  {
    id: 'telegram',
    name: 'Telegram',
    packageName: 'org.telegram.messenger',
    category: 'messaging',
    status: 'cloned',
    iconColor: '#24A1DE',
    lastLaunchedAt: new Date(Date.now() - 3600000).toISOString(),
    dataSizeBytes: 68 * 1024 * 1024,
    badgeCount: 1,
  },
  {
    id: 'vcb',
    name: 'VCB Digibank',
    packageName: 'com.VCB',
    category: 'finance',
    status: 'cloned',
    iconColor: '#005a3c',
    lastLaunchedAt: new Date(Date.now() - 7200000).toISOString(),
    dataSizeBytes: 24 * 1024 * 1024,
  },
  // Available to clone from device
  {
    id: 'facebook',
    name: 'Facebook',
    packageName: 'com.facebook.katana',
    category: 'social',
    status: 'uncloned',
    iconColor: '#1877F2',
  },
  {
    id: 'messenger',
    name: 'Messenger',
    packageName: 'com.facebook.orca',
    category: 'messaging',
    status: 'uncloned',
    iconColor: '#00B2FF',
  },
  {
    id: 'whatsapp',
    name: 'WhatsApp',
    packageName: 'com.whatsapp',
    category: 'messaging',
    status: 'uncloned',
    iconColor: '#25D366',
  },
  {
    id: 'tiktok',
    name: 'TikTok',
    packageName: 'com.zhiliaoapp.musically',
    category: 'social',
    status: 'uncloned',
    iconColor: '#000000',
  },
  {
    id: 'mbbank',
    name: 'MB Bank',
    packageName: 'com.mbmobile',
    category: 'finance',
    status: 'uncloned',
    iconColor: '#1e40af',
  },
  {
    id: 'binance',
    name: 'Binance',
    packageName: 'com.binance.dev',
    category: 'finance',
    status: 'uncloned',
    iconColor: '#f59e0b',
  },
  {
    id: 'twitter',
    name: 'X (Twitter)',
    packageName: 'com.twitter.android',
    category: 'social',
    status: 'uncloned',
    iconColor: '#111827',
  },
];

export class CloneService {
  private static STATE_KEY = 'pv_clone_state_v2';
  private static APPS_KEY = 'pv_clone_apps_v2';

  loadState(): CloneProfileState {
    try {
      const raw = localStorage.getItem(CloneService.STATE_KEY);
      if (raw) return JSON.parse(raw);
    } catch {}
    return {
      engine: 'work_profile',
      isProvisioned: true,
      isPaused: false,
      profileUserId: 10,
      shizukuAvailable: false,
      dpcAdminGranted: true,
    };
  }

  saveState(state: CloneProfileState): void {
    try {
      localStorage.setItem(CloneService.STATE_KEY, JSON.stringify(state));
    } catch (err) {
      console.error('Failed to save clone state:', err);
    }
  }

  loadApps(): CloneApp[] {
    try {
      const raw = localStorage.getItem(CloneService.APPS_KEY);
      if (raw) {
        const parsed = JSON.parse(raw);
        // Ensure built-in apps are present
        const hasGallery = parsed.some((a: CloneApp) => a.id === 'gallery');
        if (hasGallery) return parsed;
      }
    } catch {}
    return [...CATALOG_PRESETS];
  }

  saveApps(apps: CloneApp[]): void {
    try {
      localStorage.setItem(CloneService.APPS_KEY, JSON.stringify(apps));
    } catch (err) {
      console.error('Failed to save clone apps:', err);
    }
  }

  switchEngine(targetEngine: CloneEngineMode, currentState: CloneProfileState): CloneProfileState {
    const next: CloneProfileState = {
      ...currentState,
      engine: targetEngine,
      profileUserId: targetEngine === 'work_profile' ? 10 : 999,
    };
    this.saveState(next);
    return next;
  }

  togglePauseProfile(currentState: CloneProfileState, apps: CloneApp[]): {
    state: CloneProfileState;
    apps: CloneApp[];
  } {
    const nextPaused = !currentState.isPaused;
    const nextState: CloneProfileState = {
      ...currentState,
      isPaused: nextPaused,
    };
    const nextApps = apps.map((app) => {
      if (app.status === 'cloned' && !app.isBuiltinSecureApp && nextPaused) {
        return { ...app, status: 'paused' as const };
      }
      if (app.status === 'paused' && !nextPaused) {
        return { ...app, status: 'cloned' as const };
      }
      return app;
    });

    this.saveState(nextState);
    this.saveApps(nextApps);
    return { state: nextState, apps: nextApps };
  }

  cloneApp(appId: string, apps: CloneApp[]): CloneApp[] {
    const next = apps.map((a) => {
      if (a.id === appId) {
        return {
          ...a,
          status: 'cloned' as const,
          dataSizeBytes: 18 * 1024 * 1024,
          lastLaunchedAt: new Date().toISOString(),
        };
      }
      return a;
    });
    this.saveApps(next);
    return next;
  }

  removeClone(appId: string, apps: CloneApp[]): CloneApp[] {
    const next = apps.map((a) => {
      if (a.id === appId) {
        return {
          ...a,
          status: 'uncloned' as const,
          dataSizeBytes: undefined,
          lastLaunchedAt: undefined,
        };
      }
      return a;
    });
    this.saveApps(next);
    return next;
  }

  addCustomPackage(name: string, packageName: string, apps: CloneApp[]): CloneApp[] {
    const newApp: CloneApp = {
      id: `custom-${Date.now()}`,
      name: name.trim(),
      packageName: packageName.trim(),
      category: 'custom',
      status: 'cloned',
      iconColor: '#00a389',
      dataSizeBytes: 14 * 1024 * 1024,
      lastLaunchedAt: new Date().toISOString(),
    };
    const next = [...apps, newApp];
    this.saveApps(next);
    return next;
  }
}
