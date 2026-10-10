import React from 'react';
import { CloneApp, VaultItem } from '../../../types';
import { LocalVaultRepository } from '../../vault/vaultRepository';
import { ZaloAppView } from './ZaloAppView';
import { TelegramAppView } from './TelegramAppView';
import { WhatsAppAppView } from './WhatsAppAppView';
import { SecureNotesAppView } from './SecureNotesAppView';
import { SecureCameraAppView } from './SecureCameraAppView';
import { SecureFilesAppView } from './SecureFilesAppView';
import { BankingAppView } from './BankingAppView';
import { SocialAppView } from './SocialAppView';
import { BrowserHome } from '../../browser/BrowserHome';
import { ChevronLeft } from 'lucide-react';

interface ClonedAppRunnerProps {
  app: CloneApp;
  onBack: () => void;
  repository: LocalVaultRepository;
  vaultMedia?: VaultItem[];
  onOpenGallery?: () => void;
}

export const ClonedAppRunner: React.FC<ClonedAppRunnerProps> = ({
  app,
  onBack,
  repository,
  vaultMedia = [],
  onOpenGallery,
}) => {
  const pkg = app.packageName.toLowerCase();
  const id = app.id.toLowerCase();

  // 1. Zalo
  if (id.includes('zalo') || pkg.includes('zalo')) {
    return <ZaloAppView onBack={onBack} vaultMedia={vaultMedia} />;
  }

  // 2. Telegram
  if (id.includes('telegram') || pkg.includes('telegram')) {
    return <TelegramAppView onBack={onBack} vaultMedia={vaultMedia} />;
  }

  // 3. WhatsApp
  if (id.includes('whatsapp') || pkg.includes('whatsapp')) {
    return <WhatsAppAppView onBack={onBack} vaultMedia={vaultMedia} />;
  }

  // 4. Secure Camera
  if (id === 'camera' || pkg.includes('camera')) {
    return (
      <SecureCameraAppView
        onBack={onBack}
        repository={repository}
        onOpenGallery={onOpenGallery}
      />
    );
  }

  // 5. Secure Notes
  if (id === 'notes' || pkg.includes('notes')) {
    return <SecureNotesAppView onBack={onBack} repository={repository} />;
  }

  // 6. My Files
  if (id === 'files' || pkg.includes('files') || pkg.includes('filemanager')) {
    return <SecureFilesAppView onBack={onBack} repository={repository} />;
  }

  // 7. Secure Browser
  if (id === 'browser' || pkg.includes('browser') || pkg.includes('chrome')) {
    return (
      <div className="flex flex-col h-full bg-white dark:bg-[#101718] overflow-hidden">
        <div className="p-2.5 bg-zinc-900 text-white flex items-center justify-between border-b border-zinc-800">
          <button
            onClick={onBack}
            className="flex items-center gap-1 text-xs text-zinc-300 hover:text-white"
          >
            <ChevronLeft className="w-4 h-4" />
            <span>Thư mục Bảo mật</span>
          </button>
          <span className="text-xs font-bold font-mono text-teal-400">Trình duyệt Riêng tư</span>
          <div className="w-4" />
        </div>
        <div className="flex-1 overflow-hidden">
          <BrowserHome repository={repository} clearOnClose={true} />
        </div>
      </div>
    );
  }

  // 8. Banking & Finance
  if (
    app.category === 'finance' ||
    id.includes('bank') ||
    pkg.includes('vcb') ||
    pkg.includes('mbbank') ||
    pkg.includes('techcombank') ||
    pkg.includes('binance')
  ) {
    return <BankingAppView appName={app.name} onBack={onBack} />;
  }

  // 9. Social Media (Facebook, Messenger, TikTok, Twitter/X, Instagram)
  if (
    app.category === 'social' ||
    id.includes('facebook') ||
    id.includes('messenger') ||
    id.includes('tiktok') ||
    id.includes('twitter') ||
    id.includes('instagram') ||
    pkg.includes('katana') ||
    pkg.includes('orca')
  ) {
    return (
      <SocialAppView appName={app.name} packageName={app.packageName} onBack={onBack} />
    );
  }

  // 10. Generic Custom App Sandbox View
  return (
    <div className="flex flex-col h-full bg-[#12181a] text-white select-none overflow-hidden font-sans">
      <div className="p-3 bg-[#192225] border-b border-zinc-800 flex items-center justify-between shrink-0">
        <button onClick={onBack} className="p-1 rounded-full hover:bg-white/10">
          <ChevronLeft className="w-5 h-5" />
        </button>
        <div className="text-center">
          <h3 className="text-xs font-bold flex items-center justify-center gap-1.5">
            <span>{app.name}</span>
            <span className="text-[10px] text-teal-400 font-mono">(Isolated Sandbox)</span>
          </h3>
          <p className="text-[10px] text-zinc-400 font-mono">{app.packageName}</p>
        </div>
        <div className="w-6" />
      </div>

      <div className="flex-1 overflow-y-auto p-4 space-y-4">
        <div className="p-4 rounded-3xl bg-zinc-900 border border-zinc-800 text-center space-y-3">
          <div
            className="w-16 h-16 rounded-2xl mx-auto flex items-center justify-center font-bold text-xl text-white shadow-xl"
            style={{ backgroundColor: app.iconColor }}
          >
            {app.name.slice(0, 1)}
          </div>
          <div>
            <h4 className="text-sm font-bold text-white">{app.name} Sandbox</h4>
            <p className="text-xs text-zinc-400 mt-1 max-w-xs mx-auto">
              Ứng dụng đang chạy trong môi trường bảo mật Thư mục Bảo mật. Toàn bộ dữ liệu, bộ nhớ đệm và phiên đăng nhập được mã hóa riêng biệt.
            </p>
          </div>
        </div>

        <div className="p-3.5 rounded-2xl bg-[#192225] border border-zinc-800 space-y-2 text-xs">
          <div className="flex items-center justify-between text-zinc-400">
            <span>Dung lượng dữ liệu:</span>
            <span className="font-mono text-white">
              {((app.dataSizeBytes || 16 * 1024 * 1024) / (1024 * 1024)).toFixed(1)} MB
            </span>
          </div>
          <div className="flex items-center justify-between text-zinc-400">
            <span>Hồ sơ người dùng:</span>
            <span className="font-mono text-teal-400">User ID 10 (Work Profile)</span>
          </div>
          <div className="flex items-center justify-between text-zinc-400">
            <span>Mã hóa phần cứng:</span>
            <span className="font-mono text-emerald-400">Active (AES-256)</span>
          </div>
        </div>

        <button
          onClick={onBack}
          className="w-full py-3 rounded-2xl bg-teal-500 hover:bg-teal-400 text-zinc-950 font-bold text-xs shadow-lg transition-colors"
        >
          Quay lại Thư mục Bảo mật
        </button>
      </div>
    </div>
  );
};
