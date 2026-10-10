import React, { useState } from 'react';
import { CloneApp } from '../../../types';
import { LocalVaultRepository } from '../../vault/vaultRepository';
import { SecureNotesAppView } from './SecureNotesAppView';
import { SecureCameraAppView } from './SecureCameraAppView';
import { SecureFilesAppView } from './SecureFilesAppView';
import { SecureAudioRecorder } from '../../audio/SecureAudioRecorder';
import { BrowserHome } from '../../browser/BrowserHome';
import { ChevronLeft, Smartphone, AlertCircle, Play, Shield } from 'lucide-react';
import { nativeCloneBridge } from '../nativeCloneBridge';

interface ClonedAppRunnerProps {
  app: CloneApp;
  onBack: () => void;
  repository: LocalVaultRepository;
  onOpenGallery?: () => void;
}

export const ClonedAppRunner: React.FC<ClonedAppRunnerProps> = ({
  app,
  onBack,
  repository,
  onOpenGallery,
}) => {
  const [launchStatus, setLaunchStatus] = useState<string | null>(null);
  const [isLaunching, setIsLaunching] = useState(false);

  // 1. Built-in Secure Camera
  if (app.id === 'camera' || app.iconType === 'camera') {
    return (
      <SecureCameraAppView
        onBack={onBack}
        repository={repository}
        onOpenGallery={onOpenGallery}
      />
    );
  }

  // 2. Built-in Secure Notes
  if (app.id === 'notes' || app.iconType === 'notes') {
    return <SecureNotesAppView onBack={onBack} repository={repository} />;
  }

  // 3. Built-in Secure Files
  if (app.id === 'files' || app.iconType === 'files') {
    return <SecureFilesAppView onBack={onBack} repository={repository} />;
  }

  // 4. Built-in Secure Audio
  if (app.id === 'audio' || app.iconType === 'audio') {
    return <SecureAudioRecorder onBack={onBack} repository={repository} />;
  }

  // 5. Built-in Ephemeral Browser
  if (app.id === 'browser' || app.iconType === 'browser') {
    return <BrowserHome repository={repository} />;
  }

  // 6. External Native Clone App (No fake React mocks! Real native launch handling)
  const handleLaunchNative = async () => {
    setIsLaunching(true);
    setLaunchStatus(null);
    try {
      const status = await nativeCloneBridge.getProfileStatus();
      if (!status.profileExists || !status.profileUserId) {
        setLaunchStatus('Hồ sơ clone chưa được khởi tạo trên thiết bị Android qua Shizuku.');
        return;
      }
      const res = await nativeCloneBridge.launchPackageInProfile({
        packageName: app.packageName,
        profileUserId: status.profileUserId,
      });
      if (res.success) {
        setLaunchStatus('Đã gửi yêu cầu khởi chạy ứng dụng đến Android OS.');
      } else {
        setLaunchStatus('Android OS từ chối yêu cầu khởi chạy gói ứng dụng.');
      }
    } catch (err) {
      setLaunchStatus(
        err instanceof Error
          ? err.message
          : 'Không thể khởi chạy: Cầu nối Shizuku UserService chưa sẵn sàng trên phiên bản này.'
      );
    } finally {
      setIsLaunching(false);
    }
  };

  return (
    <div className="flex flex-col h-full bg-[#0d1314] text-zinc-100 select-none overflow-hidden font-sans">
      <header className="px-4 py-3 bg-[#131b1d] border-b border-zinc-800 flex items-center justify-between shrink-0">
        <div className="flex items-center gap-2.5">
          <button onClick={onBack} className="p-1 rounded-full hover:bg-zinc-800">
            <ChevronLeft className="w-5 h-5" />
          </button>
          <div>
            <h3 className="text-sm font-bold text-white">{app.name}</h3>
            <p className="text-[10px] text-zinc-400 font-mono">{app.packageName}</p>
          </div>
        </div>
      </header>

      <div className="flex-1 p-6 flex flex-col items-center justify-center text-center space-y-4">
        <div
          className="w-20 h-20 rounded-3xl flex items-center justify-center text-white shadow-xl"
          style={{ backgroundColor: app.iconColor || '#00a389' }}
        >
          <Smartphone className="w-10 h-10" />
        </div>

        <div>
          <h2 className="text-base font-bold text-white">{app.name}</h2>
          <p className="text-xs text-zinc-400 mt-1 font-mono">{app.packageName}</p>
        </div>

        <div className="p-4 rounded-2xl bg-[#141e21] border border-zinc-800 text-left max-w-sm space-y-2 text-xs">
          <div className="flex items-center gap-2 text-teal-400 font-bold">
            <Shield className="w-4 h-4" />
            <span>Không gian ứng dụng nhân bản Android</span>
          </div>
          <p className="text-zinc-300 leading-relaxed text-[11px]">
            Ứng dụng được chạy trong hồ sơ người dùng riêng biệt{' '}
            <code className="text-teal-300 font-mono">android.os.usertype.profile.CLONE</code> thông qua
            dịch vụ Shizuku UserService. Dữ liệu tài khoản, bộ nhớ đệm và tệp tin hoàn toàn độc lập với ứng dụng chính.
          </p>
        </div>

        {launchStatus && (
          <div className="p-3 rounded-xl bg-amber-950/60 border border-amber-800/60 text-amber-300 text-xs flex items-center gap-2 max-w-sm text-left">
            <AlertCircle className="w-4 h-4 shrink-0 text-amber-400" />
            <span>{launchStatus}</span>
          </div>
        )}

        <button
          onClick={handleLaunchNative}
          disabled={isLaunching}
          className="px-6 py-3 rounded-2xl bg-teal-500 hover:bg-teal-400 text-zinc-950 font-bold text-xs flex items-center gap-2 shadow-lg active:scale-95 transition-all disabled:opacity-50"
        >
          <Play className="w-4 h-4 fill-current" />
          <span>{isLaunching ? 'Đang gửi lệnh...' : 'Mở ứng dụng trên Android'}</span>
        </button>
      </div>
    </div>
  );
};
