import { AppSettings, DEFAULT_SETTINGS } from '../../types';

export class AppSettingsStore {
  private static KEY = 'app_settings_v1';

  load(): AppSettings {
    try {
      const raw = localStorage.getItem(AppSettingsStore.KEY);
      if (!raw) return { ...DEFAULT_SETTINGS };
      const parsed = JSON.parse(raw);
      return {
        ...DEFAULT_SETTINGS,
        ...parsed,
      };
    } catch {
      return { ...DEFAULT_SETTINGS };
    }
  }

  save(settings: AppSettings): void {
    try {
      localStorage.setItem(AppSettingsStore.KEY, JSON.stringify(settings));
    } catch (err) {
      console.error('Failed to save settings:', err);
    }
  }
}
