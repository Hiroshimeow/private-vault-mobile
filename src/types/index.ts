export type CoverPreference = 'calculator' | 'notes';

export type VaultItemKind = 'note' | 'image' | 'video' | 'document' | 'unknown';

export interface VaultItem {
  id: string;
  kind: VaultItemKind;
  createdAt: string; // ISO string
  name?: string;
  size?: number;
}

export interface AppSettings {
  cover: CoverPreference;
  panicShakeEnabled: boolean;
  panicFaceDownEnabled: boolean;
  shakeThresholdG: number;
  faceDownDelayMs: number;
  autoLockSeconds: number;
  biometricsEnabled: boolean;
  browserClearOnClose: boolean;
  confirmExport: boolean;
  darkMode: boolean;
}

export const DEFAULT_SETTINGS: AppSettings = {
  cover: 'calculator',
  panicShakeEnabled: true,
  panicFaceDownEnabled: false,
  shakeThresholdG: 2.5,
  faceDownDelayMs: 1200,
  autoLockSeconds: 0,
  biometricsEnabled: false,
  browserClearOnClose: true,
  confirmExport: true,
  darkMode: false,
};

export interface BrowserProfile {
  id: string;
  label: string;
}

export type CloneEngineMode = 'work_profile' | 'shizuku_clone';

export interface CloneApp {
  id: string;
  name: string;
  packageName: string;
  category: 'social' | 'messaging' | 'finance' | 'tools' | 'custom';
  status: 'uncloned' | 'cloned' | 'paused';
  iconColor: string;
  lastLaunchedAt?: string;
  dataSizeBytes?: number;
}

export interface CloneProfileState {
  engine: CloneEngineMode;
  isProvisioned: boolean;
  isPaused: boolean;
  profileUserId: number;
  shizukuAvailable: boolean;
  dpcAdminGranted: boolean;
}
