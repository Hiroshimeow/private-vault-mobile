import React, { useState, useMemo, useEffect } from 'react';
import {
  Layers,
  Image as ImageIcon,
  Globe,
  Settings,
  Lock,
  HardDrive,
} from 'lucide-react';
import { AppSettings, VaultItem } from '../../types';
import { LocalVaultRepository } from './vaultRepository';
import { VaultGallery } from '../gallery/VaultGallery';
import { BrowserHome } from '../browser/BrowserHome';
import { SettingsHome } from '../settings/SettingsHome';
import { CloneAppsHome } from '../apps/CloneAppsHome';
import { CloneService } from '../apps/cloneService';
import { SecureFilesAppView } from '../apps/running/SecureFilesAppView';

interface SecretWorkspaceProps {
  onLock: () => void;
  settings: AppSettings;
  onSettingsChanged: (next: AppSettings) => void;
  vaultRepository: LocalVaultRepository;
  onTriggerPanic: () => void;
  onResetPin: () => void;
}

export const SecretWorkspace: React.FC<SecretWorkspaceProps> = ({
  onLock,
  settings,
  onSettingsChanged,
  vaultRepository,
  onTriggerPanic,
  onResetPin,
}) => {
  const [activeTab, setActiveTab] = useState<'apps' | 'gallery' | 'browser' | 'files' | 'settings'>('apps');
  const [vaultMedia, setVaultMedia] = useState<VaultItem[]>([]);
  const cloneService = useMemo(() => new CloneService(), []);

  // Pre-load media list so cloned apps (like Zalo/Telegram) have access to attach vault photos
  const reloadVaultMedia = async () => {
    try {
      const items = await vaultRepository.list();
      setVaultMedia(items.filter((i) => i.kind === 'image' || i.kind === 'video'));
    } catch (e) {
      console.error(e);
    }
  };

  useEffect(() => {
    reloadVaultMedia();
  }, [vaultRepository]);

  const titles = {
    apps: 'Thư mục Bảo mật',
    gallery: 'Bộ sưu tập Bảo mật',
    browser: 'Trình duyệt Riêng tư',
    files: 'File của bạn',
    settings: 'Cài đặt Bảo mật',
  };

  return (
    <div className="flex flex-col h-full w-full bg-[#0d1314] text-zinc-100 select-none overflow-hidden font-sans">
      {/* Top Main Status Bar */}
      <header className="px-4 py-3 border-b border-zinc-800 bg-[#131b1d] flex items-center justify-between shrink-0 shadow-xs">
        <div className="flex items-center gap-2">
          <div className="w-2 h-2 rounded-full bg-teal-400 animate-pulse" />
          <h1 className="text-base font-bold tracking-tight text-white flex items-center gap-2">
            <span>{titles[activeTab]}</span>
          </h1>
        </div>
        <button
          onClick={onLock}
          title="Khóa ngay lập tức"
          className="flex items-center gap-1.5 px-3 py-1.5 rounded-xl border border-zinc-700 bg-zinc-800/80 text-zinc-200 text-xs font-semibold hover:bg-zinc-700 active:scale-95 transition-all shadow-xs"
        >
          <Lock className="w-3.5 h-3.5 text-teal-400" />
          <span>Khóa</span>
        </button>
      </header>

      {/* Main Content Body with Persistent Keep-Alive Tabs */}
      <main className="flex-1 overflow-hidden relative">
        <div className={activeTab === 'apps' ? 'h-full w-full' : 'hidden'}>
          <CloneAppsHome
            cloneService={cloneService}
            vaultRepository={vaultRepository}
            vaultMedia={vaultMedia}
            onLock={onLock}
            onOpenGallery={() => setActiveTab('gallery')}
          />
        </div>

        <div className={activeTab === 'gallery' ? 'h-full w-full' : 'hidden'}>
          <VaultGallery
            repository={vaultRepository}
            confirmExport={settings.confirmExport}
          />
        </div>

        <div className={activeTab === 'browser' ? 'h-full w-full' : 'hidden'}>
          <BrowserHome
            repository={vaultRepository}
            clearOnClose={settings.browserClearOnClose}
          />
        </div>

        <div className={activeTab === 'files' ? 'h-full w-full' : 'hidden'}>
          <SecureFilesAppView
            onBack={() => setActiveTab('apps')}
            repository={vaultRepository}
          />
        </div>

        <div className={activeTab === 'settings' ? 'h-full w-full' : 'hidden'}>
          <SettingsHome
            settings={settings}
            onSettingsChanged={onSettingsChanged}
            onTriggerPanic={onTriggerPanic}
            onResetPin={onResetPin}
          />
        </div>
      </main>

      {/* Bottom Navigation Tabs (Samsung One UI Navigation Bar) */}
      <nav className="h-16 border-t border-zinc-800 bg-[#131b1d] flex items-center justify-around px-2 shrink-0 shadow-lg">
        <button
          onClick={() => setActiveTab('apps')}
          className={`flex flex-col items-center justify-center gap-1 flex-1 py-1 rounded-xl transition-all ${
            activeTab === 'apps'
              ? 'text-teal-400 font-bold'
              : 'text-zinc-400 hover:text-zinc-200 font-normal'
          }`}
        >
          <div
            className={`px-3 py-1 rounded-full transition-colors ${
              activeTab === 'apps' ? 'bg-teal-500/20' : 'bg-transparent'
            }`}
          >
            <Layers className="w-5 h-5" />
          </div>
          <span className="text-[10px]">Ứng dụng</span>
        </button>

        <button
          onClick={() => setActiveTab('gallery')}
          className={`flex flex-col items-center justify-center gap-1 flex-1 py-1 rounded-xl transition-all ${
            activeTab === 'gallery'
              ? 'text-teal-400 font-bold'
              : 'text-zinc-400 hover:text-zinc-200 font-normal'
          }`}
        >
          <div
            className={`px-3 py-1 rounded-full transition-colors ${
              activeTab === 'gallery' ? 'bg-teal-500/20' : 'bg-transparent'
            }`}
          >
            <ImageIcon className="w-5 h-5" />
          </div>
          <span className="text-[10px]">Bộ sưu tập</span>
        </button>

        <button
          onClick={() => setActiveTab('browser')}
          className={`flex flex-col items-center justify-center gap-1 flex-1 py-1 rounded-xl transition-all ${
            activeTab === 'browser'
              ? 'text-teal-400 font-bold'
              : 'text-zinc-400 hover:text-zinc-200 font-normal'
          }`}
        >
          <div
            className={`px-3 py-1 rounded-full transition-colors ${
              activeTab === 'browser' ? 'bg-teal-500/20' : 'bg-transparent'
            }`}
          >
            <Globe className="w-5 h-5" />
          </div>
          <span className="text-[10px]">Trình duyệt</span>
        </button>

        <button
          onClick={() => setActiveTab('files')}
          className={`flex flex-col items-center justify-center gap-1 flex-1 py-1 rounded-xl transition-all ${
            activeTab === 'files'
              ? 'text-teal-400 font-bold'
              : 'text-zinc-400 hover:text-zinc-200 font-normal'
          }`}
        >
          <div
            className={`px-3 py-1 rounded-full transition-colors ${
              activeTab === 'files' ? 'bg-teal-500/20' : 'bg-transparent'
            }`}
          >
            <HardDrive className="w-5 h-5" />
          </div>
          <span className="text-[10px]">File</span>
        </button>

        <button
          onClick={() => setActiveTab('settings')}
          className={`flex flex-col items-center justify-center gap-1 flex-1 py-1 rounded-xl transition-all ${
            activeTab === 'settings'
              ? 'text-teal-400 font-bold'
              : 'text-zinc-400 hover:text-zinc-200 font-normal'
          }`}
        >
          <div
            className={`px-3 py-1 rounded-full transition-colors ${
              activeTab === 'settings' ? 'bg-teal-500/20' : 'bg-transparent'
            }`}
          >
            <Settings className="w-5 h-5" />
          </div>
          <span className="text-[10px]">Cài đặt</span>
        </button>
      </nav>
    </div>
  );
};
