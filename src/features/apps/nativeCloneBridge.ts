/**
 * Typed Capacitor Native Bridge for Android OS-level profile.CLONE via Shizuku UserService.
 * Strictly fail-closed: reports honest platform status when native bridge is unavailable.
 */

export interface NativeCloneBridgePlugin {
  isShizukuAvailable(): Promise<{ available: boolean; authorized: boolean }>;
  requestShizukuPermission(): Promise<{ granted: boolean }>;
  checkCloneSupport(): Promise<{ supported: boolean; reason?: string }>;
  getProfileStatus(): Promise<{
    profileExists: boolean;
    profileUserId: number | null;
    isPaused: boolean;
  }>;
  createCloneProfile(): Promise<{ profileUserId: number }>;
  removeCloneProfile(options: { profileUserId: number }): Promise<{ success: boolean }>;
  listInstalledPackages(options?: { profileUserId?: number }): Promise<{
    packages: Array<{ packageName: string; appName: string }>;
  }>;
  clonePackage(options: { packageName: string; profileUserId: number }): Promise<{ success: boolean }>;
  removePackage(options: { packageName: string; profileUserId: number }): Promise<{ success: boolean }>;
  launchPackageInProfile(options: { packageName: string; profileUserId: number }): Promise<{ success: boolean }>;
  setProfilePaused(options: { profileUserId: number; paused: boolean }): Promise<{ success: boolean }>;
}

class NativeCloneBridgeImpl implements NativeCloneBridgePlugin {
  private getPlugin(): NativeCloneBridgePlugin | null {
    if (typeof window !== 'undefined' && (window as any).Capacitor?.Plugins?.NativeCloneBridge) {
      return (window as any).Capacitor.Plugins.NativeCloneBridge as NativeCloneBridgePlugin;
    }
    return null;
  }

  async isShizukuAvailable(): Promise<{ available: boolean; authorized: boolean }> {
    const plugin = this.getPlugin();
    if (plugin) {
      return await plugin.isShizukuAvailable();
    }
    // Honest status on web / non-Android
    return { available: false, authorized: false };
  }

  async requestShizukuPermission(): Promise<{ granted: boolean }> {
    const plugin = this.getPlugin();
    if (plugin) {
      return await plugin.requestShizukuPermission();
    }
    return { granted: false };
  }

  async checkCloneSupport(): Promise<{ supported: boolean; reason?: string }> {
    const plugin = this.getPlugin();
    if (plugin) {
      return await plugin.checkCloneSupport();
    }
    return {
      supported: false,
      reason: 'Cầu nối Shizuku UserService chỉ khả dụng trên Android. Không hỗ trợ trên môi trường trình duyệt web.',
    };
  }

  async getProfileStatus(): Promise<{
    profileExists: boolean;
    profileUserId: number | null;
    isPaused: boolean;
  }> {
    const plugin = this.getPlugin();
    if (plugin) {
      return await plugin.getProfileStatus();
    }
    return {
      profileExists: false,
      profileUserId: null,
      isPaused: false,
    };
  }

  async createCloneProfile(): Promise<{ profileUserId: number }> {
    const plugin = this.getPlugin();
    if (plugin) {
      return await plugin.createCloneProfile();
    }
    throw new Error('Cầu nối Shizuku UserService không khả dụng để tạo hồ sơ profile.CLONE.');
  }

  async removeCloneProfile(options: { profileUserId: number }): Promise<{ success: boolean }> {
    const plugin = this.getPlugin();
    if (plugin) {
      return await plugin.removeCloneProfile(options);
    }
    return { success: false };
  }

  async listInstalledPackages(options?: { profileUserId?: number }): Promise<{
    packages: Array<{ packageName: string; appName: string }>;
  }> {
    const plugin = this.getPlugin();
    if (plugin) {
      return await plugin.listInstalledPackages(options);
    }
    return { packages: [] };
  }

  async clonePackage(options: { packageName: string; profileUserId: number }): Promise<{ success: boolean }> {
    const plugin = this.getPlugin();
    if (plugin) {
      return await plugin.clonePackage(options);
    }
    throw new Error('Không thể nhân bản: Cầu nối Shizuku không khả dụng.');
  }

  async removePackage(options: { packageName: string; profileUserId: number }): Promise<{ success: boolean }> {
    const plugin = this.getPlugin();
    if (plugin) {
      return await plugin.removePackage(options);
    }
    return { success: false };
  }

  async launchPackageInProfile(options: { packageName: string; profileUserId: number }): Promise<{ success: boolean }> {
    const plugin = this.getPlugin();
    if (plugin) {
      return await plugin.launchPackageInProfile(options);
    }
    throw new Error('Không thể khởi chạy ứng dụng: Cầu nối Shizuku trên Android chưa được kích hoạt.');
  }

  async setProfilePaused(options: { profileUserId: number; paused: boolean }): Promise<{ success: boolean }> {
    const plugin = this.getPlugin();
    if (plugin) {
      return await plugin.setProfilePaused(options);
    }
    return { success: false };
  }
}

export const nativeCloneBridge = new NativeCloneBridgeImpl();
