import React, { useState, useEffect, useRef } from 'react';
import {
  Plus,
  Shield,
  Trash2,
  Image as ImageIcon,
  Camera,
  FileText,
  Globe,
  HardDrive,
  Mic,
  Smartphone,
  AlertCircle,
  CheckCircle2,
  FileCode,
  RefreshCw,
} from 'lucide-react';
import { CloneApp, CloneProfileState, VaultItem } from '../../types';
import { CloneService } from './cloneService';
import { LocalVaultRepository } from '../vault/vaultRepository';
import { ClonedAppRunner } from './running/ClonedAppRunner';
import { ApkParser } from './apkInstaller';

interface CloneAppsHomeProps {
  cloneService: CloneService;
  vaultRepository: LocalVaultRepository;
  vaultMedia?: VaultItem[];
  onLock: () => void;
  onOpenGallery: () => void;
}

export const CloneAppsHome: React.FC<CloneAppsHomeProps> = ({
  cloneService,
  vaultRepository,
  onOpenGallery,
}) => {
  const [profileState, setProfileState] = useState<CloneProfileState>({
    engine: 'shizuku_clone',
    isProvisioned: false,
    isPaused: false,
    profileUserId: null,
    shizukuAvailable: false,
    dpcAdminGranted: false,
  });

  const [apps, setApps] = useState<CloneApp[]>(() => cloneService.loadApps());
  const [runningApp, setRunningApp] = useState<CloneApp | null>(null);
  const [toast, setToast] = useState<string | null>(null);
  const [isCheckingBridge, setIsCheckingBridge] = useState(false);
  const [isAddApkModalOpen, setIsAddApkModalOpen] = useState(false);
  const [apkError, setApkError] = useState<string | null>(null);
  const [isProcessingApk, setIsProcessingApk] = useState(false);

  const apkFileInputRef = useRef<HTMLInputElement | null>(null);

  const showToast = (msg: string) => {
    setToast(msg);
    setTimeout(() => setToast(null), 3500);
  };

  const refreshProfileState = async () => {
    setIsCheckingBridge(true);
    try {
      const state = await cloneService.getProfileState();
      setProfileState(state);
      if (state.shizukuAvailable) {
        showToast('Dịch vụ Shizuku đã kết nối thành công.');
      }
    } catch (err) {
      console.error(err);
    } finally {
      setIsCheckingBridge(false);
    }
  };

  useEffect(() => {
    refreshProfileState();
  }, []);

  const handleLaunchApp = (app: CloneApp) => {
    if (app.id === 'gallery') {
      onOpenGallery();
      return;
    }
    setRunningApp(app);
  };

  const handleSelectApkFile = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file) {
      setTimeout(() => {
        window.dispatchEvent(new CustomEvent('vault-suspend-lock', { detail: false }));
      }, 500);
      return;
    }

    setIsProcessingApk(true);
    setApkError(null);

    try {
      // 1. Real binary APK validation
      const meta = await ApkParser.parseApkFile(file);

      // 2. Read bytes and save to encrypted vault
      const buffer = await file.arrayBuffer();
      const bytes = new Uint8Array(buffer);

      await vaultRepository.addBytes(bytes, {
        kind: 'document',
        name: file.name,
        mimeType: 'application/vnd.android.package-archive',
        sourceHash: meta.sha256,
        album: 'Bộ cài đặt APK',
      });

      // 3. Register app entry
      const newClone = ApkParser.createCloneAppFromApk(meta);
      const nextApps = [...apps, newClone];
      setApps(nextApps);
      cloneService.saveApps(nextApps);

      showToast(`Đã sao chép và mã hóa gói APK "${meta.appName}" vào Vault.`);
      setIsAddApkModalOpen(false);
    } catch (err) {
      setApkError(err instanceof Error ? err.message : 'Tệp APK không hợp lệ.');
    } finally {
      setIsProcessingApk(false);
      if (apkFileInputRef.current) apkFileInputRef.current.value = '';
      setTimeout(() => {
        window.dispatchEvent(new CustomEvent('vault-suspend-lock', { detail: false }));
      }, 1000);
    }
  };

  const handleOpenApkPicker = () => {
    window.dispatchEvent(new CustomEvent('vault-suspend-lock', { detail: true }));
    apkFileInputRef.current?.click();
  };

  const handleDeleteApp = async (app: CloneApp, e: React.MouseEvent) => {
    e.stopPropagation();
    if (app.isBuiltinSecureApp) return;
    if (!window.confirm(`Xóa ứng dụng "${app.name}" khỏi danh sách?`)) return;

    try {
      const next = await cloneService.removeClone(app, profileState.profileUserId);
      setApps(next);
      showToast(`Đã gỡ bỏ ứng dụng "${app.name}".`);
    } catch (err) {
      alert('Lỗi gỡ ứng dụng: ' + (err instanceof Error ? err.message : String(err)));
    }
  };

  const getBuiltinIcon = (type?: string) => {
    switch (type) {
      case 'gallery':
        return <ImageIcon className="w-6 h-6" />;
      case 'camera':
        return <Camera className="w-6 h-6" />;
      case 'notes':
        return <FileText className="w-6 h-6" />;
      case 'files':
        return <HardDrive className="w-6 h-6" />;
      case 'browser':
        return <Globe className="w-6 h-6" />;
      case 'audio':
        return <Mic className="w-6 h-6" />;
      default:
        return <Smartphone className="w-6 h-6" />;
    }
  };

  if (runningApp) {
    return (
      <ClonedAppRunner
        app={runningApp}
        onBack={() => setRunningApp(null)}
        repository={vaultRepository}
        onOpenGallery={onOpenGallery}
      />
    );
  }

  const builtinApps = apps.filter((a) => a.isBuiltinSecureApp);
  const customClones = apps.filter((a) => !a.isBuiltinSecureApp);

  return (
    <div className="flex flex-col h-full bg-[#0d1314] text-zinc-100 select-none overflow-hidden font-sans">
      <input
        type="file"
        ref={apkFileInputRef}
        onChange={handleSelectApkFile}
        accept=".apk,application/vnd.android.package-archive"
        className="hidden"
      />

      {toast && (
        <div className="p-3 bg-teal-950/90 border-b border-teal-800 text-teal-300 text-xs text-center flex items-center justify-center gap-2 font-medium">
          <CheckCircle2 className="w-4 h-4" />
          <span>{toast}</span>
        </div>
      )}

      <div className="flex-1 overflow-y-auto p-4 space-y-5">
        {/* Shizuku profile.CLONE Architecture Status Card */}
        <div className="p-4 rounded-2xl bg-[#141e21] border border-zinc-800 space-y-3 shadow-xs">
          <div className="flex items-center justify-between">
            <div className="flex items-center gap-2">
              <Shield className="w-4 h-4 text-teal-400" />
              <span className="text-xs font-bold text-white uppercase tracking-wider">
                Hồ sơ Clone Hệ điều hành
              </span>
            </div>
            <button
              onClick={refreshProfileState}
              disabled={isCheckingBridge}
              className="text-xs text-teal-400 hover:text-teal-300 flex items-center gap-1"
            >
              <RefreshCw className={`w-3.5 h-3.5 ${isCheckingBridge ? 'animate-spin' : ''}`} />
              <span>Kiểm tra</span>
            </button>
          </div>

          <div className="grid grid-cols-2 gap-2 text-xs">
            <div className="p-2.5 rounded-xl bg-zinc-900 border border-zinc-800">
              <span className="text-[10px] text-zinc-400 block">Dịch vụ Shizuku</span>
              <span
                className={`text-xs font-bold font-mono mt-0.5 block ${
                  profileState.shizukuAvailable ? 'text-teal-400' : 'text-zinc-400'
                }`}
              >
                {profileState.shizukuAvailable ? 'Đã kích hoạt' : 'Chưa kết nối (Web)'}
              </span>
            </div>

            <div className="p-2.5 rounded-xl bg-zinc-900 border border-zinc-800">
              <span className="text-[10px] text-zinc-400 block">Kiểu hồ sơ Clone</span>
              <span className="text-xs font-bold font-mono text-zinc-300 mt-0.5 block">
                profile.CLONE
              </span>
            </div>
          </div>

          <p className="text-[11px] text-zinc-400 leading-relaxed">
            Nhân bản ứng dụng thật sử dụng cơ chế người dùng độc lập của Android OS. Các tiện ích bảo mật bên dưới hoạt động ngoại tuyến và được mã hóa bằng AES-256.
          </p>
        </div>

        {/* Section 1: Built-in Secure Vault Tools */}
        <div className="space-y-3">
          <div className="flex items-center justify-between px-1">
            <h3 className="text-xs font-bold text-zinc-400 uppercase tracking-wider">
              Tiện ích Bảo mật Tích hợp
            </h3>
          </div>

          <div className="grid grid-cols-3 gap-3">
            {builtinApps.map((app) => (
              <div
                key={app.id}
                onClick={() => handleLaunchApp(app)}
                className="p-3.5 rounded-2xl bg-[#141e21] border border-zinc-800 hover:border-zinc-700 cursor-pointer transition-all active:scale-95 flex flex-col items-center justify-center text-center space-y-2 aspect-square shadow-xs group"
              >
                <div
                  className="w-11 h-11 rounded-2xl flex items-center justify-center text-white shadow-md transition-transform group-hover:scale-105"
                  style={{ backgroundColor: app.iconColor }}
                >
                  {getBuiltinIcon(app.iconType)}
                </div>
                <span className="text-xs font-semibold text-zinc-200 truncate w-full">
                  {app.name}
                </span>
              </div>
            ))}
          </div>
        </div>

        {/* Section 2: Cloned Apps & APK Packages */}
        <div className="space-y-3">
          <div className="flex items-center justify-between px-1">
            <h3 className="text-xs font-bold text-zinc-400 uppercase tracking-wider">
              Ứng dụng Nhân bản & Gói APK ({customClones.length})
            </h3>
            <button
              onClick={() => setIsAddApkModalOpen(true)}
              className="text-xs text-teal-400 hover:underline flex items-center gap-1 font-semibold"
            >
              <Plus className="w-3.5 h-3.5" />
              <span>+ Thêm APK</span>
            </button>
          </div>

          {customClones.length === 0 ? (
            <div className="py-12 border border-dashed border-zinc-800 rounded-2xl flex flex-col items-center justify-center text-center p-4 space-y-2">
              <FileCode className="w-8 h-8 text-zinc-600" />
              <p className="text-xs font-medium text-zinc-400">Chưa có gói ứng dụng nhân bản nào</p>
              <p className="text-[11px] text-zinc-500 max-w-xs">
                Chọn tệp APK từ bộ nhớ để xác minh tính hợp lệ và mã hóa an toàn vào Vault.
              </p>
              <button
                onClick={() => setIsAddApkModalOpen(true)}
                className="mt-2 px-3 py-1.5 rounded-xl bg-zinc-800 hover:bg-zinc-700 text-teal-400 text-xs font-semibold"
              >
                + Chọn tệp APK
              </button>
            </div>
          ) : (
            <div className="grid grid-cols-1 gap-2.5">
              {customClones.map((app) => (
                <div
                  key={app.id}
                  onClick={() => handleLaunchApp(app)}
                  className="p-3.5 rounded-2xl bg-[#141e21] border border-zinc-800 hover:border-zinc-700 cursor-pointer transition-all flex items-center justify-between shadow-xs"
                >
                  <div className="flex items-center gap-3 min-w-0">
                    <div
                      className="w-10 h-10 rounded-xl flex items-center justify-center text-white shrink-0 shadow-xs"
                      style={{ backgroundColor: app.iconColor }}
                    >
                      <Smartphone className="w-5 h-5" />
                    </div>
                    <div className="min-w-0">
                      <h4 className="text-xs font-bold text-white truncate">{app.name}</h4>
                      <p className="text-[10px] text-zinc-400 font-mono truncate mt-0.5">
                        {app.packageName}
                      </p>
                    </div>
                  </div>

                  <div className="flex items-center gap-2">
                    <button
                      onClick={(e) => handleDeleteApp(app, e)}
                      className="p-1.5 text-zinc-400 hover:text-rose-400"
                      title="Xóa ứng dụng"
                    >
                      <Trash2 className="w-4 h-4" />
                    </button>
                  </div>
                </div>
              ))}
            </div>
          )}
        </div>
      </div>

      {/* Modal: Add APK */}
      {isAddApkModalOpen && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/80 backdrop-blur-xs p-4">
          <div className="w-full max-w-sm bg-[#141e21] border border-zinc-800 rounded-3xl p-5 shadow-2xl space-y-4">
            <div className="flex items-center justify-between pb-2 border-b border-zinc-800">
              <h3 className="text-sm font-bold text-white">Thêm gói APK vào Vault</h3>
              <button
                onClick={() => {
                  setIsAddApkModalOpen(false);
                  setApkError(null);
                }}
                className="text-zinc-400 hover:text-white"
              >
                ✕
              </button>
            </div>

            <p className="text-xs text-zinc-300 leading-relaxed">
              Trình phân tích APK nhị phân sẽ kiểm tra chữ ký nén ZIP, quét tệp{' '}
              <code className="text-teal-300 font-mono">AndroidManifest.xml</code> và tính toán mã băm SHA-256 trước khi mã hóa vào Vault.
            </p>

            {apkError && (
              <div className="p-3 bg-rose-950/70 border border-rose-800 text-rose-300 text-xs rounded-xl flex items-center gap-2">
                <AlertCircle className="w-4 h-4 shrink-0" />
                <span>{apkError}</span>
              </div>
            )}

            <div className="p-2.5 rounded-xl bg-teal-950/40 border border-teal-800/40 text-[11px] text-teal-300">
              ✓ <strong>Bảo toàn tệp gốc:</strong> Tệp .APK trên điện thoại không bị xóa hoặc di chuyển; app chỉ đọc và sao chép an toàn vào Thư mục Bảo mật.
            </div>

            <div className="pt-2">
              <button
                onClick={handleOpenApkPicker}
                disabled={isProcessingApk}
                className="w-full py-3 rounded-xl bg-teal-500 hover:bg-teal-400 text-zinc-950 font-bold text-xs flex items-center justify-center gap-2 shadow-sm disabled:opacity-50"
              >
                <FileCode className="w-4 h-4" />
                <span>{isProcessingApk ? 'Đang phân tích tệp...' : 'Chọn tệp .APK từ máy'}</span>
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
};
