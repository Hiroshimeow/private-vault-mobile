export type CoverPreference = 'calculator' | 'notes' | 'calendar' | 'weather' | 'clock';

export type VaultItemKind = 'note' | 'image' | 'video' | 'audio' | 'document' | 'unknown';

export interface VaultItem {
  id: string;
  kind: VaultItemKind;
  createdAt: string; // ISO string
  name?: string;
  size?: number;
  mimeType?: string;
  sourceHash?: string;
  album?: string;
  isFavorite?: boolean;
  thumbnail?: string;
  width?: number;
  height?: number;
  duration?: string; // For videos/audio e.g. "0:42"
}

export interface VaultAlbum {
  id: string;
  name: string;
  coverId?: string;
  count?: number;
  createdAt: string;
}

export interface AppSettings {
  cover: CoverPreference;
  appTitle: string;
  appIconTheme: string;
  panicShakeEnabled: boolean;
  panicFaceDownEnabled: boolean;
  shakeThresholdG: number;
  faceDownDelayMs: number;
  autoLockSeconds: number;
  biometricsEnabled: boolean;
  browserClearOnClose: boolean;
  browserUserAgent: 'mobile' | 'desktop';
  confirmExport: boolean;
  darkMode: boolean;
  decoyPinEnabled: boolean;
  hideNotifications: boolean;
}

export const DEFAULT_SETTINGS: AppSettings = {
  cover: 'calculator',
  appTitle: 'Máy tính',
  appIconTheme: 'calculator',
  panicShakeEnabled: true,
  panicFaceDownEnabled: false,
  shakeThresholdG: 2.5,
  faceDownDelayMs: 1200,
  autoLockSeconds: 0,
  biometricsEnabled: false,
  browserClearOnClose: true,
  browserUserAgent: 'mobile',
  confirmExport: true,
  darkMode: true,
  decoyPinEnabled: false,
  hideNotifications: true,
};

export interface BrowserProfile {
  id: string;
  label: string;
}

export type CloneEngineMode = 'shizuku_clone' | 'work_profile';

export interface CloneApp {
  id: string;
  name: string;
  packageName: string;
  category: 'system' | 'social' | 'messaging' | 'dating' | 'finance' | 'tools' | 'custom';
  status: 'uncloned' | 'cloned' | 'paused';
  iconColor: string;
  iconType?: string;
  lastLaunchedAt?: string;
  dataSizeBytes?: number;
  badgeCount?: number;
  isBuiltinSecureApp?: boolean;
}

export interface CloneProfileState {
  engine: CloneEngineMode;
  isProvisioned: boolean;
  isPaused: boolean;
  profileUserId: number | null;
  shizukuAvailable: boolean;
  dpcAdminGranted: boolean;
}
