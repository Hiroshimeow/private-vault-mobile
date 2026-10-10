import { CloneApp, CloneProfileState, CloneEngineMode } from '../../types';
import { LocalVaultRepository } from '../vault/vaultRepository';

const DEFAULT_APPS: CloneApp[] = [
  {
    id: 'zalo',
    name: 'Zalo',
    packageName: 'com.zing.zalo',
    category: 'messaging',
    status: 'cloned',
    iconColor: '#0068ff',
    lastLaunchedAt: new Date(Date.now() - 3600000).toISOString(),
    dataSizeBytes: 42 * 1024 * 1024,
  },
  {
    id: 'telegram',
    name: 'Telegram',
    packageName: 'org.telegram.messenger',
    category: 'messaging',
    status: 'cloned',
    iconColor: '#24A1DE',
    lastLaunchedAt: new Date(Date.now() - 7200000).toISOString(),
    dataSizeBytes: 86 * 1024 * 1024,
  },
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
    id: 'vcb',
    name: 'VCB Digibank',
    packageName: 'com.VCB',
    category: 'finance',
    status: 'uncloned',
    iconColor: '#005a3c',
  },
];

export class CloneService {
  private static STATE_KEY = 'pv_clone_state_v1';
  private static APPS_KEY = 'pv_clone_apps_v1';

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
      if (raw) return JSON.parse(raw);
    } catch {}
    return [...DEFAULT_APPS];
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
      if (app.status === 'cloned' && nextPaused) {
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
          dataSizeBytes: 12 * 1024 * 1024,
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
      iconColor: '#315e63',
      dataSizeBytes: 8 * 1024 * 1024,
      lastLaunchedAt: new Date().toISOString(),
    };
    const next = [newApp, ...apps];
    this.saveApps(next);
    return next;
  }

  async sendFileToVault(
    app: CloneApp,
    fileName: string,
    content: string,
    vaultRepo: LocalVaultRepository
  ): Promise<void> {
    const encoder = new TextEncoder();
    const bytes = encoder.encode(content);
    await vaultRepo.addBytes(bytes, {
      kind: 'document',
      name: `[Clone-${app.name}] ${fileName}`,
    });
  }
}
