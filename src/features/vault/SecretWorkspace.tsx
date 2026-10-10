import React, { useState, useMemo } from 'react';
import { Archive, Layers, Globe, Settings, Lock } from 'lucide-react';
import { AppSettings } from '../../types';
import { LocalVaultRepository } from './vaultRepository';
import { VaultHome } from './VaultHome';
import { BrowserHome } from '../browser/BrowserHome';
import { SettingsHome } from '../settings/SettingsHome';
import { CloneAppsHome } from '../apps/CloneAppsHome';
import { CloneService } from '../apps/cloneService';

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
  const [activeTab, setActiveTab] = useState<'apps' | 'vault' | 'browser' | 'settings'>('apps');
  const cloneService = useMemo(() => new CloneService(), []);

  const titles = {
    apps: 'Clone Space',
    vault: 'Vault',
    browser: 'Browser',
    settings: 'Settings',
  };

  return (
    <div className="flex flex-col h-full max-w-md mx-auto bg-zinc-50 dark:bg-[#101718] select-none">
      <header className="px-5 py-3.5 border-b border-zinc-200/80 dark:border-zinc-800/80 bg-white dark:bg-[#172021] flex items-center justify-between shrink-0 shadow-xs">
        <div className="flex items-center gap-2">
          <div className="w-2 h-2 rounded-full bg-teal-500 animate-pulse" />
          <h1 className="text-lg font-bold tracking-tight text-zinc-900 dark:text-zinc-100">
            {titles[activeTab]}
          </h1>
        </div>
        <button
          onClick={onLock}
          title="Lock now"
          className="flex items-center gap-1.5 px-3 py-1.5 rounded-xl border border-zinc-200 dark:border-zinc-700 bg-zinc-50 dark:bg-zinc-800 text-zinc-700 dark:text-zinc-200 text-xs font-semibold hover:bg-zinc-100 dark:hover:bg-zinc-700 active:scale-95 transition-all"
        >
          <Lock className="w-3.5 h-3.5 text-[#315e63] dark:text-[#78aeb3]" />
          <span>Lock</span>
        </button>
      </header>

      <main className="flex-1 overflow-hidden relative">
        {activeTab === 'apps' && (
          <CloneAppsHome
            cloneService={cloneService}
            vaultRepository={vaultRepository}
            onLock={onLock}
          />
        )}
        {activeTab === 'vault' && (
          <VaultHome
            repository={vaultRepository}
            confirmExport={settings.confirmExport}
          />
        )}
        {activeTab === 'browser' && (
          <BrowserHome
            repository={vaultRepository}
            clearOnClose={settings.browserClearOnClose}
          />
        )}
        {activeTab === 'settings' && (
          <SettingsHome
            settings={settings}
            onSettingsChanged={onSettingsChanged}
            onTriggerPanic={onTriggerPanic}
            onResetPin={onResetPin}
          />
        )}
      </main>

      <nav className="h-16 border-t border-zinc-200/80 dark:border-zinc-800/80 bg-white dark:bg-[#172021] flex items-center justify-around px-2 shrink-0 shadow-xs">
        <button
          onClick={() => setActiveTab('apps')}
          className={`flex flex-col items-center justify-center gap-1 flex-1 py-1 rounded-xl transition-all ${
            activeTab === 'apps'
              ? 'text-[#315e63] dark:text-[#78aeb3] font-semibold'
              : 'text-zinc-400 hover:text-zinc-600 dark:hover:text-zinc-300 font-normal'
          }`}
        >
          <div
            className={`px-3 py-1 rounded-full ${
              activeTab === 'apps'
                ? 'bg-teal-100/70 dark:bg-teal-950/80'
                : 'bg-transparent'
            }`}
          >
            <Layers className="w-5 h-5" />
          </div>
          <span className="text-[11px]">Clone</span>
        </button>

        <button
          onClick={() => setActiveTab('vault')}
          className={`flex flex-col items-center justify-center gap-1 flex-1 py-1 rounded-xl transition-all ${
            activeTab === 'vault'
              ? 'text-[#315e63] dark:text-[#78aeb3] font-semibold'
              : 'text-zinc-400 hover:text-zinc-600 dark:hover:text-zinc-300 font-normal'
          }`}
        >
          <div
            className={`px-3 py-1 rounded-full ${
              activeTab === 'vault'
                ? 'bg-teal-100/70 dark:bg-teal-950/80'
                : 'bg-transparent'
            }`}
          >
            <Archive className="w-5 h-5" />
          </div>
          <span className="text-[11px]">Vault</span>
        </button>

        <button
          onClick={() => setActiveTab('browser')}
          className={`flex flex-col items-center justify-center gap-1 flex-1 py-1 rounded-xl transition-all ${
            activeTab === 'browser'
              ? 'text-[#315e63] dark:text-[#78aeb3] font-semibold'
              : 'text-zinc-400 hover:text-zinc-600 dark:hover:text-zinc-300 font-normal'
          }`}
        >
          <div
            className={`px-3 py-1 rounded-full ${
              activeTab === 'browser'
                ? 'bg-teal-100/70 dark:bg-teal-950/80'
                : 'bg-transparent'
            }`}
          >
            <Globe className="w-5 h-5" />
          </div>
          <span className="text-[11px]">Browser</span>
        </button>

        <button
          onClick={() => setActiveTab('settings')}
          className={`flex flex-col items-center justify-center gap-1 flex-1 py-1 rounded-xl transition-all ${
            activeTab === 'settings'
              ? 'text-[#315e63] dark:text-[#78aeb3] font-semibold'
              : 'text-zinc-400 hover:text-zinc-600 dark:hover:text-zinc-300 font-normal'
          }`}
        >
          <div
            className={`px-3 py-1 rounded-full ${
              activeTab === 'settings'
                ? 'bg-teal-100/70 dark:bg-teal-950/80'
                : 'bg-transparent'
            }`}
          >
            <Settings className="w-5 h-5" />
          </div>
          <span className="text-[11px]">Settings</span>
        </button>
      </nav>
    </div>
  );
};
