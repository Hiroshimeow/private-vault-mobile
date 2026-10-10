import React, { useState, useRef } from 'react';
import {
  Plus,
  Shield,
  Play,
  Trash2,
  Lock,
  Pause,
  CheckCircle2,
  Image as ImageIcon,
  Camera,
  FileText,
  Globe,
  HardDrive,
  MoreVertical,
  Check,
  X,
  FileCode,
  Terminal,
  Cpu,
  Smartphone,
  Copy,
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
  vaultMedia = [],
  onLock,
  onOpenGallery,
}) => {
  const [state, setState] = useState<CloneProfileState>(() => cloneService.loadState());
  const [apps, setApps] = useState<CloneApp[]>(() => cloneService.loadApps());
  const [runningApp, setRunningApp] = useState<CloneApp | null>(null);

  // Add apps modal
  const [isAddAppsOpen, setIsAddAppsOpen] = useState(false);
  const [selectedToAdd, setSelectedToAdd] = useState<Set<string>>(new Set());
  const [customName, setCustomName] = useState('');
  const [customPackage, setCustomPackage] = useState('');

  // Native Architecture modal
  const [isArchModalOpen, setIsArchModalOpen] = useState(false);
  const [copiedCmd, setCopiedCmd] = useState(false);

  // App action modal
  const [appToManage, setAppToManage] = useState<CloneApp | null>(null);
  const [toast, setToast] = useState<string | null>(null);

  const apkFileInputRef = useRef<HTMLInputElement | null>(null);

  const showToast = (msg: string) => {
    setToast(msg);
    setTimeout(() => setToast(null), 3000);
  };

  const clonedApps = apps.filter((a) => a.status === 'cloned' || a.status === 'paused');
  const unclonedApps = apps.filter((a) => a.status === 'uncloned');

  const handleLaunchApp = (app: CloneApp) => {
    if (app.id === 'gallery') {
      onOpenGallery();
      return;
    }
    setRunningApp(app);
  };

  const handleTogglePause = () => {
    const res = cloneService.togglePauseProfile(state, apps);
    setState(res.state);
    setApps(res.apps);
    showToast(
      res.state.isPaused
        ? 'Đã đóng băng tất cả ứng dụng nhân bản'
        : 'Đã mở khóa các ứng dụng nhân bản'
    );
  };

  const handleAddSelectedApps = () => {
    let next = [...apps];
    selectedToAdd.forEach((appId) => {
      next = cloneService.cloneApp(appId, next);
    });

    if (customName.trim() && customPackage.trim()) {
      next = cloneService.addCustomPackage(customName, customPackage, next);
      setCustomName('');
      setCustomPackage('');
    }

    setApps(next);
    setSelectedToAdd(new Set());
    setIsAddAppsOpen(false);
    showToast(`Đã thêm ứng dụng vào Thư mục Bảo mật`);
  };

  // Upload and parse real APK file
  const handleInstallApk = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file) return;

    try {
      showToast('Đang phân tích gói tệp APK...');
      const metadata = await ApkParser.parseApkFile(file);
      const newClone = ApkParser.createCloneAppFromApk(metadata);

      // Save APK binary into Vault repository
      const buffer = await file.arrayBuffer();
      await vaultRepository.addBytes(new Uint8Array(buffer), {
        kind: 'document',
        name: file.name,
        album: 'Gói cài đặt APK',
      });

      const nextApps = [newClone, ...apps];
      setApps(nextApps);
      cloneService.saveApps(nextApps);

      showToast(`Đã cài đặt thành công "${metadata.appName}" (${(metadata.fileSizeBytes / (1024 * 1024)).toFixed(1)} MB)`);
    } catch (err) {
      console.error(err);
      showToast('Lỗi khi đọc file APK');
    } finally {
      if (apkFileInputRef.current) apkFileInputRef.current.value = '';
    }
  };

  const handleRemoveApp = (app: CloneApp) => {
    if (app.isBuiltinSecureApp) {
      showToast('Ứng dụng hệ thống không thể gỡ bỏ');
      return;
    }
    const next = cloneService.removeClone(app.id, apps);
    setApps(next);
    setAppToManage(null);
    showToast(`Đã gỡ ${app.name} khỏi Thư mục Bảo mật`);
  };

  const handleClearAppData = (app: CloneApp) => {
    showToast(`Đã xóa dữ liệu và bộ nhớ đệm của ${app.name}`);
    setAppToManage(null);
  };

  const getAppIcon = (app: CloneApp) => {
    if (app.iconType === 'gallery' || app.id === 'gallery') {
      return <ImageIcon className="w-6 h-6 text-white" />;
    }
    if (app.iconType === 'camera' || app.id === 'camera') {
      return <Camera className="w-6 h-6 text-white" />;
    }
    if (app.iconType === 'notes' || app.id === 'notes') {
      return <FileText className="w-6 h-6 text-white" />;
    }
    if (app.iconType === 'browser' || app.id === 'browser') {
      return <Globe className="w-6 h-6 text-white" />;
    }
    if (app.iconType === 'files' || app.id === 'files') {
      return <HardDrive className="w-6 h-6 text-white" />;
    }
    return (
      <span className="font-bold text-sm tracking-tight text-white">
        {app.name.slice(0, 1)}
      </span>
    );
  };

  // If an app is running, render the full app runtime
  if (runningApp) {
    return (
      <ClonedAppRunner
        app={runningApp}
        onBack={() => setRunningApp(null)}
        repository={vaultRepository}
        vaultMedia={vaultMedia}
        onOpenGallery={onOpenGallery}
      />
    );
  }

  return (
    <div className="flex flex-col h-full bg-[#0e1416] text-zinc-100 select-none overflow-hidden font-sans">
      <input
        type="file"
        ref={apkFileInputRef}
        onChange={handleInstallApk}
        accept=".apk"
        className="hidden"
      />

      {/* Top Header */}
      <div className="px-4 py-3 bg-[#141d20] border-b border-zinc-800 flex items-center justify-between shrink-0 shadow-xs">
        <div className="flex items-center gap-2.5">
          <div className="w-7 h-7 rounded-lg bg-teal-500/20 text-teal-400 flex items-center justify-center">
            <Shield className="w-4 h-4" />
          </div>
          <div>
            <h2 className="text-sm font-bold tracking-tight text-white flex items-center gap-2">
              <span>Thư mục Bảo mật</span>
              <span className="text-[10px] px-1.5 py-0.2 rounded-md bg-teal-500/20 text-teal-300 font-mono">
                Samsung OneUI
              </span>
            </h2>
            <p className="text-[10px] text-zinc-400">
              {clonedApps.length} ứng dụng an toàn · Không gian cách ly
            </p>
          </div>
        </div>

        <div className="flex items-center gap-2">
          <button
            onClick={() => setIsArchModalOpen(true)}
            className="p-1.5 rounded-xl bg-zinc-800 text-zinc-300 hover:text-white hover:bg-zinc-700 transition-colors shadow-xs"
            title="Kiến trúc Android Native"
          >
            <Cpu className="w-4 h-4 text-teal-400" />
          </button>

          <button
            onClick={handleTogglePause}
            className={`px-2 py-1 rounded-xl text-xs font-semibold flex items-center gap-1 transition-colors ${
              state.isPaused
                ? 'bg-amber-500/20 text-amber-300 border border-amber-500/30'
                : 'text-zinc-400 hover:text-white hover:bg-zinc-800'
            }`}
            title={state.isPaused ? 'Mở lại các ứng dụng' : 'Đóng băng ứng dụng'}
          >
            {state.isPaused ? <Play className="w-3 h-3" /> : <Pause className="w-3 h-3" />}
            <span className="text-[11px]">{state.isPaused ? 'Mở' : 'Băng'}</span>
          </button>

          <button
            onClick={onLock}
            className="p-1.5 rounded-xl bg-zinc-800 text-zinc-300 hover:text-white hover:bg-zinc-700 transition-colors shadow-xs"
            title="Khóa ngay lập tức"
          >
            <Lock className="w-4 h-4" />
          </button>

          <button
            onClick={() => setIsAddAppsOpen(true)}
            className="p-1.5 rounded-xl bg-teal-500 text-zinc-950 hover:bg-teal-400 transition-colors shadow-xs"
            title="Thêm ứng dụng vào Thư mục Bảo mật"
          >
            <Plus className="w-4 h-4" />
          </button>
        </div>
      </div>

      {/* Main Apps Grid (Samsung Secure Folder Style) */}
      <div className="flex-1 overflow-y-auto p-4 space-y-5">
        <div className="grid grid-cols-4 gap-y-5 gap-x-3">
          {clonedApps.map((app) => (
            <div
              key={app.id}
              className="flex flex-col items-center text-center group cursor-pointer relative"
              onClick={() => handleLaunchApp(app)}
              onContextMenu={(e) => {
                e.preventDefault();
                setAppToManage(app);
              }}
            >
              {/* App Icon (Squircle) */}
              <div
                className="w-14 h-14 rounded-2xl flex items-center justify-center shadow-lg relative group-hover:scale-105 active:scale-95 transition-all"
                style={{ backgroundColor: app.iconColor }}
              >
                {getAppIcon(app)}

                {/* Secure Badge icon on bottom-right of icon */}
                <div className="absolute -bottom-1 -right-1 w-4 h-4 rounded-full bg-teal-500 text-zinc-950 flex items-center justify-center shadow-md">
                  <Shield className="w-2.5 h-2.5" />
                </div>

                {/* Badge count if any */}
                {app.badgeCount && (
                  <div className="absolute -top-1 -right-1 px-1.5 py-0.2 rounded-full bg-rose-500 text-white text-[9px] font-bold">
                    {app.badgeCount}
                  </div>
                )}
              </div>

              {/* App Label */}
              <span className="text-[11px] font-medium text-zinc-200 mt-2 truncate w-full group-hover:text-teal-300 transition-colors">
                {app.name}
              </span>

              {/* More button */}
              <button
                onClick={(e) => {
                  e.stopPropagation();
                  setAppToManage(app);
                }}
                className="opacity-0 group-hover:opacity-100 absolute top-0 right-0 p-1 rounded-full bg-black/60 text-zinc-400 hover:text-white transition-opacity"
              >
                <MoreVertical className="w-3 h-3" />
              </button>
            </div>
          ))}

          {/* Add Apps Tile */}
          <div
            onClick={() => setIsAddAppsOpen(true)}
            className="flex flex-col items-center text-center cursor-pointer group"
          >
            <div className="w-14 h-14 rounded-2xl border-2 border-dashed border-zinc-700 hover:border-teal-400 text-zinc-400 hover:text-teal-400 flex items-center justify-center group-hover:scale-105 active:scale-95 transition-all">
              <Plus className="w-6 h-6" />
            </div>
            <span className="text-[11px] font-medium text-zinc-400 group-hover:text-teal-400 mt-2">
              Thêm ứng dụng
            </span>
          </div>

          {/* Install APK Tile */}
          <div
            onClick={() => apkFileInputRef.current?.click()}
            className="flex flex-col items-center text-center cursor-pointer group"
          >
            <div className="w-14 h-14 rounded-2xl border-2 border-dashed border-teal-800 hover:border-teal-400 text-teal-400/80 hover:text-teal-400 flex items-center justify-center group-hover:scale-105 active:scale-95 transition-all bg-teal-950/20">
              <FileCode className="w-6 h-6" />
            </div>
            <span className="text-[11px] font-medium text-teal-400 mt-2">
              Cài file APK
            </span>
          </div>
        </div>

        {/* Info Banner */}
        <div className="p-3.5 rounded-2xl bg-[#141d20] border border-zinc-800/80 text-xs text-zinc-400 space-y-2">
          <div className="flex items-center justify-between">
            <div className="flex items-center gap-1.5 text-teal-400 font-bold">
              <CheckCircle2 className="w-4 h-4" />
              <span>Chạy ứng dụng độc lập 100%</span>
            </div>
            <button
              onClick={() => setIsArchModalOpen(true)}
              className="text-[11px] text-teal-400 hover:underline"
            >
              Xem cơ chế
            </button>
          </div>
          <p className="text-[11px] leading-relaxed text-zinc-400">
            Chạm vào bất kỳ ứng dụng nào để mở và sử dụng bình thường. Bạn cũng có thể bấm <strong>"Cài file APK"</strong> để tải file <code>.apk</code> từ máy tính/điện thoại vào không gian bảo mật.
          </p>
        </div>
      </div>

      {/* Modal: Add Apps into Secure Folder */}
      {isAddAppsOpen && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/75 backdrop-blur-xs p-4">
          <div className="w-full max-w-sm bg-[#141d20] border border-zinc-800 rounded-3xl p-5 shadow-2xl flex flex-col max-h-[85vh] overflow-hidden space-y-4">
            <div className="flex items-center justify-between pb-2 border-b border-zinc-800">
              <div>
                <h3 className="text-sm font-bold text-white">Thêm ứng dụng vào Thư mục</h3>
                <p className="text-[10px] text-zinc-400">Chọn ứng dụng trên máy để nhân bản</p>
              </div>
              <button
                onClick={() => setIsAddAppsOpen(false)}
                className="text-zinc-400 hover:text-white"
              >
                <X className="w-5 h-5" />
              </button>
            </div>

            {/* Quick APK upload shortcut inside modal */}
            <div
              onClick={() => apkFileInputRef.current?.click()}
              className="p-3 rounded-2xl border border-teal-500/40 bg-teal-500/10 hover:bg-teal-500/20 text-teal-300 flex items-center justify-between cursor-pointer transition-colors"
            >
              <div className="flex items-center gap-2.5">
                <FileCode className="w-5 h-5" />
                <div>
                  <h4 className="text-xs font-bold text-white">Cài đặt từ tệp APK (.apk)</h4>
                  <p className="text-[10px] text-teal-300/80">Chọn file APK từ máy để cài đặt</p>
                </div>
              </div>
              <span className="text-xs font-semibold px-2 py-1 rounded-lg bg-teal-500 text-zinc-950">
                Chọn file
              </span>
            </div>

            {/* App Catalog Checklist */}
            <div className="flex-1 overflow-y-auto space-y-2 pr-1">
              <span className="text-[10px] font-bold uppercase tracking-wider text-zinc-500">
                Ứng dụng có sẵn ({unclonedApps.length})
              </span>

              {unclonedApps.map((u) => {
                const isChecked = selectedToAdd.has(u.id);
                return (
                  <div
                    key={u.id}
                    onClick={() => {
                      const next = new Set(selectedToAdd);
                      if (next.has(u.id)) next.delete(u.id);
                      else next.add(u.id);
                      setSelectedToAdd(next);
                    }}
                    className={`p-2.5 rounded-2xl border flex items-center justify-between cursor-pointer transition-colors ${
                      isChecked
                        ? 'bg-teal-500/10 border-teal-500 text-white'
                        : 'bg-zinc-900 border-zinc-800 text-zinc-300 hover:border-zinc-700'
                    }`}
                  >
                    <div className="flex items-center gap-3">
                      <div
                        className="w-9 h-9 rounded-xl flex items-center justify-center font-bold text-white text-xs shadow-xs"
                        style={{ backgroundColor: u.iconColor }}
                      >
                        {u.name.slice(0, 1)}
                      </div>
                      <div>
                        <div className="text-xs font-bold text-white">{u.name}</div>
                        <div className="text-[10px] text-zinc-400 font-mono">
                          {u.packageName}
                        </div>
                      </div>
                    </div>

                    <div
                      className={`w-5 h-5 rounded-md flex items-center justify-center ${
                        isChecked ? 'bg-teal-500 text-zinc-950' : 'border border-zinc-600'
                      }`}
                    >
                      {isChecked && <Check className="w-3.5 h-3.5 font-bold" />}
                    </div>
                  </div>
                );
              })}

              {/* Custom app package */}
              <div className="pt-3 border-t border-zinc-800 space-y-2">
                <span className="text-[10px] font-bold uppercase tracking-wider text-zinc-500">
                  Hoặc cài đặt theo tên gói APK
                </span>
                <input
                  type="text"
                  value={customName}
                  onChange={(e) => setCustomName(e.target.value)}
                  placeholder="Tên ứng dụng (vd: Signal)"
                  className="w-full p-2 rounded-xl bg-zinc-900 border border-zinc-800 text-xs text-white placeholder-zinc-500 focus:outline-none focus:border-teal-500"
                />
                <input
                  type="text"
                  value={customPackage}
                  onChange={(e) => setCustomPackage(e.target.value)}
                  placeholder="Package name (vd: org.thoughtcrime.securesms)"
                  className="w-full p-2 rounded-xl bg-zinc-900 border border-zinc-800 text-xs font-mono text-white placeholder-zinc-500 focus:outline-none focus:border-teal-500"
                />
              </div>
            </div>

            <div className="flex justify-end gap-2 pt-2 border-t border-zinc-800">
              <button
                onClick={() => setIsAddAppsOpen(false)}
                className="px-4 py-2 rounded-xl text-xs text-zinc-400 hover:text-white hover:bg-zinc-800"
              >
                Hủy
              </button>
              <button
                onClick={handleAddSelectedApps}
                disabled={selectedToAdd.size === 0 && (!customName.trim() || !customPackage.trim())}
                className="px-5 py-2 rounded-xl text-xs font-bold bg-teal-500 text-zinc-950 disabled:opacity-40 hover:bg-teal-400 transition-colors shadow-md"
              >
                Thêm vào Thư mục
              </button>
            </div>
          </div>
        </div>
      )}

      {/* Modal: Native Architecture Guide & Technical Explanation */}
      {isArchModalOpen && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/80 backdrop-blur-xs p-4">
          <div className="w-full max-w-md bg-[#141d20] border border-zinc-800 rounded-3xl p-5 shadow-2xl flex flex-col max-h-[85vh] overflow-hidden space-y-4">
            <div className="flex items-center justify-between pb-2 border-b border-zinc-800">
              <div className="flex items-center gap-2">
                <Cpu className="w-5 h-5 text-teal-400" />
                <h3 className="text-sm font-bold text-white">Cơ chế Cài đặt & Clone Thực tế</h3>
              </div>
              <button
                onClick={() => setIsArchModalOpen(false)}
                className="text-zinc-400 hover:text-white"
              >
                <X className="w-5 h-5" />
              </button>
            </div>

            <div className="flex-1 overflow-y-auto space-y-3.5 text-xs text-zinc-300 pr-1 leading-relaxed">
              <div className="p-3 rounded-2xl bg-teal-950/40 border border-teal-800/60 space-y-1.5">
                <h4 className="font-bold text-teal-300 flex items-center gap-1.5">
                  <Smartphone className="w-4 h-4" />
                  <span>1. Khi cài trên điện thoại Android thật (Native APK)</span>
                </h4>
                <p className="text-[11px] text-zinc-300">
                  Private Vault sử dụng chuẩn <strong>Android Enterprise Work Profile (Profile Owner DPC)</strong>. Hệ điều hành Android sẽ tạo một không gian User 10 tách biệt (giống hệt Samsung Knox / Secure Folder).
                </p>
                <p className="text-[11px] text-zinc-400">
                  Lệnh hệ thống gọi ngầm: <code className="text-teal-300 font-mono">pm install-existing --user 10 &lt;package_name&gt;</code>. Khi mở app, Android sẽ mở bung file nhị phân APK thật 100% với tài khoản, thông báo đẩy và dữ liệu độc lập.
                </p>
              </div>

              <div className="p-3 rounded-2xl bg-zinc-900 border border-zinc-800 space-y-1.5">
                <h4 className="font-bold text-white flex items-center gap-1.5">
                  <Globe className="w-4 h-4 text-sky-400" />
                  <span>2. Khi chạy trên Web / Trình duyệt hiện tại</span>
                </h4>
                <p className="text-[11px] text-zinc-400">
                  Web browser không có máy ảo Android Runtime (ART) để chạy trực tiếp mã máy APK nhị phân. Do đó, Private Vault cung cấp:
                </p>
                <ul className="list-disc pl-4 space-y-1 text-[11px] text-zinc-300">
                  <li>Bộ Sandbox Runtime mô phỏng đầy đủ dữ liệu (nhắn tin, đính kèm ảnh mã hóa từ Vault Gallery, camera, ghi chú, ngân hàng).</li>
                  <li>Cho phép upload và lưu trữ file <code>.apk</code> vào kho mã hóa của Vault.</li>
                  <li>Hỗ trợ liên kết trực tiếp phiên bản Web Client chính thức (Zalo Web, Telegram Web, WhatsApp Web) để đăng nhập tài khoản 2.</li>
                </ul>
              </div>

              <div className="p-3 rounded-xl bg-zinc-950 border border-zinc-800 space-y-2">
                <div className="flex items-center justify-between text-[11px] text-zinc-400">
                  <span className="flex items-center gap-1">
                    <Terminal className="w-3.5 h-3.5 text-teal-400" />
                    <span>Lệnh kích hoạt DPC Profile Owner trên máy thật</span>
                  </span>
                  <button
                    onClick={() => {
                      navigator.clipboard.writeText('dpm set-profile-owner io.privatevault/.VaultDpcReceiver');
                      setCopiedCmd(true);
                      setTimeout(() => setCopiedCmd(false), 2000);
                    }}
                    className="text-teal-400 hover:underline flex items-center gap-1"
                  >
                    {copiedCmd ? <Check className="w-3 h-3" /> : <Copy className="w-3 h-3" />}
                    <span>{copiedCmd ? 'Đã sao chép' : 'Copy'}</span>
                  </button>
                </div>
                <div className="p-2 rounded-lg bg-zinc-900 font-mono text-[10px] text-teal-300 select-all break-all">
                  dpm set-profile-owner io.privatevault/.VaultDpcReceiver
                </div>
              </div>
            </div>

            <button
              onClick={() => setIsArchModalOpen(false)}
              className="w-full py-2.5 rounded-xl bg-teal-500 hover:bg-teal-400 text-zinc-950 font-bold text-xs"
            >
              Đã hiểu
            </button>
          </div>
        </div>
      )}

      {/* Modal: App Management Options */}
      {appToManage && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/75 backdrop-blur-xs p-4">
          <div className="w-full max-w-xs bg-[#141d20] border border-zinc-800 rounded-3xl p-5 shadow-2xl space-y-4">
            <div className="flex items-center gap-3 pb-2 border-b border-zinc-800">
              <div
                className="w-10 h-10 rounded-2xl flex items-center justify-center font-bold text-white text-sm"
                style={{ backgroundColor: appToManage.iconColor }}
              >
                {getAppIcon(appToManage)}
              </div>
              <div className="min-w-0">
                <h3 className="text-xs font-bold text-white truncate">{appToManage.name}</h3>
                <p className="text-[10px] text-zinc-400 font-mono truncate">
                  {appToManage.packageName}
                </p>
              </div>
            </div>

            <div className="space-y-1.5 text-xs">
              <button
                onClick={() => {
                  const target = appToManage;
                  setAppToManage(null);
                  handleLaunchApp(target);
                }}
                className="w-full p-2.5 rounded-xl bg-teal-500/10 hover:bg-teal-500/20 text-teal-300 font-semibold flex items-center gap-2 transition-colors"
              >
                <Play className="w-4 h-4" />
                <span>Mở ứng dụng ngay</span>
              </button>

              <button
                onClick={() => handleClearAppData(appToManage)}
                className="w-full p-2.5 rounded-xl text-zinc-300 hover:bg-zinc-800 flex items-center gap-2 transition-colors"
              >
                <HardDrive className="w-4 h-4 text-zinc-400" />
                <span>Xóa dữ liệu & cache ứng dụng</span>
              </button>

              {!appToManage.isBuiltinSecureApp && (
                <button
                  onClick={() => handleRemoveApp(appToManage)}
                  className="w-full p-2.5 rounded-xl text-rose-400 hover:bg-rose-950/40 flex items-center gap-2 transition-colors"
                >
                  <Trash2 className="w-4 h-4" />
                  <span>Gỡ khỏi Thư mục Bảo mật</span>
                </button>
              )}
            </div>

            <button
              onClick={() => setAppToManage(null)}
              className="w-full py-2 rounded-xl bg-zinc-800 hover:bg-zinc-700 text-xs text-white"
            >
              Đóng
            </button>
          </div>
        </div>
      )}

      {/* Toast */}
      {toast && (
        <div className="absolute bottom-4 left-1/2 -translate-x-1/2 z-50 px-4 py-2 rounded-xl bg-teal-500 text-zinc-950 font-bold text-xs shadow-2xl animate-in fade-in slide-in-from-bottom-2">
          {toast}
        </div>
      )}
    </div>
  );
};
