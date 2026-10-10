import React, { useState } from 'react';
import {
  Layers,
  Play,
  Trash2,
  Plus,
  Shield,
  ShieldAlert,
  FolderLock,
  Pause,
  Terminal,
  Smartphone,
  CheckCircle2,
  Lock,
} from 'lucide-react';
import { CloneApp, CloneProfileState } from '../../types';
import { CloneService } from './cloneService';
import { LocalVaultRepository } from '../vault/vaultRepository';

interface CloneAppsHomeProps {
  cloneService: CloneService;
  vaultRepository: LocalVaultRepository;
  onLock: () => void;
}

export const CloneAppsHome: React.FC<CloneAppsHomeProps> = ({
  cloneService,
  vaultRepository,
  onLock,
}) => {
  const [state, setState] = useState<CloneProfileState>(() => cloneService.loadState());
  const [apps, setApps] = useState<CloneApp[]>(() => cloneService.loadApps());
  const [activeApp, setActiveApp] = useState<CloneApp | null>(null);
  const [isAddCustomOpen, setIsAddCustomOpen] = useState(false);
  const [customName, setCustomName] = useState('');
  const [customPackage, setCustomPackage] = useState('');
  const [notification, setNotification] = useState<string | null>(null);

  // Simulation modal state for launched cloned app
  const [mockContent, setMockContent] = useState('');
  const [isSavingToVault, setIsSavingToVault] = useState(false);

  const showNotification = (msg: string) => {
    setNotification(msg);
    setTimeout(() => setNotification(null), 3500);
  };

  const handleTogglePause = () => {
    const res = cloneService.togglePauseProfile(state, apps);
    setState(res.state);
    setApps(res.apps);
    showNotification(
      res.state.isPaused
        ? 'Clone profile paused. All cloned apps frozen.'
        : 'Clone profile resumed. Apps ready.'
    );
  };

  const handleSwitchEngine = (engine: 'work_profile' | 'shizuku_clone') => {
    const nextState = cloneService.switchEngine(engine, state);
    setState(nextState);
    showNotification(
      engine === 'work_profile'
        ? 'Switched to Work Profile Engine (Profile Owner DPC, Zero-ADB).'
        : 'Switched to Shizuku Engine (profile.CLONE, requires ADB/Shizuku).'
    );
  };

  const handleClone = (appId: string) => {
    const nextApps = cloneService.cloneApp(appId, apps);
    setApps(nextApps);
    const target = nextApps.find((a) => a.id === appId);
    showNotification(`Cloned ${target?.name} into user ${state.profileUserId} sandbox.`);
  };

  const handleRemove = (appId: string) => {
    const nextApps = cloneService.removeClone(appId, apps);
    setApps(nextApps);
    showNotification('Removed cloned app from isolated sandbox.');
  };

  const handleAddCustom = (e: React.FormEvent) => {
    e.preventDefault();
    if (!customName.trim() || !customPackage.trim()) return;
    const next = cloneService.addCustomPackage(customName, customPackage, apps);
    setApps(next);
    setIsAddCustomOpen(false);
    setCustomName('');
    setCustomPackage('');
    showNotification(`Installed ${customName} (${customPackage}) into sandbox.`);
  };

  const handleSaveToVault = async () => {
    if (!activeApp || !mockContent.trim()) return;
    setIsSavingToVault(true);
    try {
      await cloneService.sendFileToVault(
        activeApp,
        `chat-export-${Date.now()}.txt`,
        mockContent,
        vaultRepository
      );
      setMockContent('');
      showNotification(`Saved data from ${activeApp.name} into AES-256-GCM Vault!`);
      setActiveApp(null);
    } catch {
      showNotification('Error saving to vault.');
    } finally {
      setIsSavingToVault(false);
    }
  };

  const clonedList = apps.filter((a) => a.status === 'cloned' || a.status === 'paused');
  const availableList = apps.filter((a) => a.status === 'uncloned');

  return (
    <div className="flex flex-col h-full bg-zinc-50 dark:bg-[#101718] overflow-hidden select-none">
      {/* Top Status & Engine Header */}
      <div className="p-3.5 bg-white dark:bg-[#172021] border-b border-zinc-200/80 dark:border-zinc-800 shrink-0 space-y-3">
        <div className="flex items-center justify-between">
          <div className="flex items-center gap-2">
            <div
              className={`w-2.5 h-2.5 rounded-full ${
                state.isPaused ? 'bg-amber-500' : 'bg-emerald-500 animate-pulse'
              }`}
            />
            <span className="text-xs font-bold uppercase tracking-wider text-zinc-900 dark:text-zinc-100">
              {state.engine === 'work_profile' ? 'Work Profile (DPC)' : 'Shizuku CLONE'}
            </span>
            <span className="text-[10px] px-1.5 py-0.5 rounded-md font-mono bg-zinc-100 dark:bg-zinc-800 text-zinc-500">
              UID {state.profileUserId}
            </span>
          </div>

          <div className="flex items-center gap-1.5">
            <button
              onClick={handleTogglePause}
              title={state.isPaused ? 'Resume cloned apps' : 'Pause / Freeze all cloned apps'}
              className={`flex items-center gap-1 px-2.5 py-1 rounded-lg text-xs font-medium transition-colors ${
                state.isPaused
                  ? 'bg-amber-100 dark:bg-amber-950/80 text-amber-800 dark:text-amber-200 border border-amber-300 dark:border-amber-800'
                  : 'bg-zinc-100 dark:bg-zinc-800 text-zinc-700 dark:text-zinc-300 hover:bg-zinc-200'
              }`}
            >
              {state.isPaused ? <Play className="w-3 h-3" /> : <Pause className="w-3 h-3" />}
              <span>{state.isPaused ? 'Resume' : 'Freeze'}</span>
            </button>
          </div>
        </div>

        {/* Engine switcher tabs */}
        <div className="grid grid-cols-2 gap-1 p-1 bg-zinc-100 dark:bg-zinc-800/80 rounded-xl">
          <button
            onClick={() => handleSwitchEngine('work_profile')}
            className={`py-1.5 rounded-lg text-xs font-semibold transition-all flex items-center justify-center gap-1.5 ${
              state.engine === 'work_profile'
                ? 'bg-white dark:bg-zinc-900 text-[#315e63] dark:text-[#78aeb3] shadow-xs'
                : 'text-zinc-500 hover:text-zinc-800 dark:hover:text-zinc-200'
            }`}
          >
            <Smartphone className="w-3.5 h-3.5" />
            <span>DPC Work Profile</span>
          </button>
          <button
            onClick={() => handleSwitchEngine('shizuku_clone')}
            className={`py-1.5 rounded-lg text-xs font-semibold transition-all flex items-center justify-center gap-1.5 ${
              state.engine === 'shizuku_clone'
                ? 'bg-white dark:bg-zinc-900 text-[#315e63] dark:text-[#78aeb3] shadow-xs'
                : 'text-zinc-500 hover:text-zinc-800 dark:hover:text-zinc-200'
            }`}
          >
            <Terminal className="w-3.5 h-3.5" />
            <span>Shizuku CLONE</span>
          </button>
        </div>

        {notification && (
          <div className="p-2 rounded-lg bg-teal-50 dark:bg-teal-950/60 border border-teal-200 dark:border-teal-900 text-teal-800 dark:text-teal-200 text-xs flex items-center gap-2 animate-in fade-in">
            <CheckCircle2 className="w-4 h-4 shrink-0" />
            <span>{notification}</span>
          </div>
        )}
      </div>

      {/* Main Content Area */}
      <div className="flex-1 overflow-y-auto p-4 space-y-5">
        {/* Active Cloned Apps Section */}
        <div>
          <div className="flex items-center justify-between mb-2">
            <div className="flex items-center gap-1.5">
              <Layers className="w-4 h-4 text-[#315e63] dark:text-[#78aeb3]" />
              <h3 className="text-xs font-bold uppercase tracking-wider text-zinc-800 dark:text-zinc-200">
                Cloned Space ({clonedList.length})
              </h3>
            </div>
            <button
              onClick={() => setIsAddCustomOpen(true)}
              className="text-xs text-[#315e63] dark:text-[#78aeb3] font-medium flex items-center gap-1 hover:underline"
            >
              <Plus className="w-3.5 h-3.5" />
              <span>Clone by Package</span>
            </button>
          </div>

          {clonedList.length === 0 ? (
            <div className="p-6 rounded-2xl bg-white dark:bg-[#172021] border border-zinc-200/80 dark:border-zinc-800 text-center space-y-2">
              <ShieldAlert className="w-8 h-8 mx-auto text-zinc-400" />
              <p className="text-xs font-semibold text-zinc-700 dark:text-zinc-300">
                No active cloned apps in this space
              </p>
              <p className="text-[11px] text-zinc-400 max-w-xs mx-auto">
                Choose an application below to instantiate an isolated clone with separate storage,
                full Google Login, and notifications.
              </p>
            </div>
          ) : (
            <div className="grid grid-cols-2 gap-2.5">
              {clonedList.map((app) => (
                <div
                  key={app.id}
                  className="p-3.5 rounded-2xl bg-white dark:bg-[#172021] border border-zinc-200/80 dark:border-zinc-800 shadow-xs flex flex-col justify-between hover:border-zinc-300 dark:hover:border-zinc-700 transition-all"
                >
                  <div className="flex items-start justify-between">
                    <div className="flex items-center gap-2">
                      <div
                        className="w-8 h-8 rounded-xl flex items-center justify-center font-bold text-white text-xs shadow-xs"
                        style={{ backgroundColor: app.iconColor }}
                      >
                        {app.name.slice(0, 1)}
                      </div>
                      <div className="min-w-0">
                        <div className="text-xs font-bold text-zinc-900 dark:text-zinc-100 truncate">
                          {app.name}
                        </div>
                        <div className="text-[10px] text-zinc-400 font-mono truncate max-w-[85px]">
                          {app.packageName}
                        </div>
                      </div>
                    </div>
                  </div>

                  <div className="mt-3 flex items-center justify-between text-[11px]">
                    <span className="text-zinc-400">
                      {app.status === 'paused' ? (
                        <span className="text-amber-500 font-medium">Frozen</span>
                      ) : (
                        `${((app.dataSizeBytes || 0) / (1024 * 1024)).toFixed(0)} MB`
                      )}
                    </span>
                    <div className="flex items-center gap-1">
                      <button
                        onClick={() => handleRemove(app.id)}
                        title="Remove clone"
                        className="p-1.5 text-zinc-400 hover:text-rose-500 rounded-lg hover:bg-zinc-100 dark:hover:bg-zinc-800 transition-colors"
                      >
                        <Trash2 className="w-3.5 h-3.5" />
                      </button>
                      <button
                        onClick={() => setActiveApp(app)}
                        title="Launch clone app"
                        disabled={app.status === 'paused'}
                        className="flex items-center gap-1 px-2.5 py-1 rounded-lg bg-[#315e63] dark:bg-[#78aeb3] text-white dark:text-zinc-950 font-semibold text-xs hover:opacity-90 disabled:opacity-40 transition-opacity"
                      >
                        <Play className="w-3 h-3 fill-current" />
                        <span>Open</span>
                      </button>
                    </div>
                  </div>
                </div>
              ))}
            </div>
          )}
        </div>

        {/* Available to Clone Section */}
        <div>
          <div className="flex items-center gap-1.5 mb-2">
            <Smartphone className="w-4 h-4 text-zinc-400" />
            <h3 className="text-xs font-bold uppercase tracking-wider text-zinc-600 dark:text-zinc-400">
              Available on Device
            </h3>
          </div>

          <div className="space-y-2">
            {availableList.map((app) => (
              <div
                key={app.id}
                className="flex items-center justify-between p-3 rounded-2xl bg-white dark:bg-[#172021] border border-zinc-200/80 dark:border-zinc-800"
              >
                <div className="flex items-center gap-3">
                  <div
                    className="w-9 h-9 rounded-xl flex items-center justify-center font-bold text-white text-xs shadow-xs"
                    style={{ backgroundColor: app.iconColor }}
                  >
                    {app.name.slice(0, 1)}
                  </div>
                  <div>
                    <div className="text-xs font-semibold text-zinc-900 dark:text-zinc-100">
                      {app.name}
                    </div>
                    <div className="text-[10px] text-zinc-400 font-mono">
                      {app.packageName}
                    </div>
                  </div>
                </div>

                <button
                  onClick={() => handleClone(app.id)}
                  className="flex items-center gap-1 px-3 py-1.5 rounded-xl border border-[#315e63] dark:border-[#78aeb3] text-[#315e63] dark:text-[#78aeb3] hover:bg-[#315e63]/10 text-xs font-semibold transition-colors"
                >
                  <Plus className="w-3.5 h-3.5" />
                  <span>Clone</span>
                </button>
              </div>
            ))}
          </div>
        </div>

        {/* Technical Architecture Info Card */}
        <div className="p-4 rounded-2xl bg-teal-50/60 dark:bg-teal-950/30 border border-teal-200/80 dark:border-teal-900/60 space-y-2">
          <div className="flex items-center gap-2 text-[#315e63] dark:text-[#78aeb3]">
            <Shield className="w-4 h-4" />
            <h4 className="text-xs font-bold">Native Sandbox Architecture</h4>
          </div>
          <p className="text-[11px] text-zinc-600 dark:text-zinc-300 leading-relaxed">
            Unlike unstable repackaging or broken container hooking, Private Vault uses native Android
            multi-user profiles. Cloned applications retain their original cryptographic signatures,
            allowing <strong>Google Sign-in</strong>, <strong>Push Notifications</strong>, and native performance.
          </p>
          <div className="text-[10px] text-zinc-400 font-mono flex items-center gap-3 pt-1">
            <span>• DevicePolicyManager (DPC)</span>
            <span>• Panic Freeze Protection</span>
            <span>• Direct-to-Vault SAF</span>
          </div>
        </div>
      </div>

      {/* Modal: Add Custom Package */}
      {isAddCustomOpen && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/60 backdrop-blur-xs p-4">
          <div className="w-full max-w-sm bg-white dark:bg-zinc-900 rounded-3xl p-5 shadow-2xl border border-zinc-200 dark:border-zinc-800 space-y-4">
            <h4 className="text-sm font-bold text-zinc-900 dark:text-zinc-100">
              Clone Custom Application
            </h4>
            <p className="text-xs text-zinc-500 dark:text-zinc-400">
              Enter the exact package name installed on this device (e.g. <code>org.thoughtcrime.securesms</code>).
            </p>
            <form onSubmit={handleAddCustom} className="space-y-3">
              <div>
                <label className="text-[11px] font-medium text-zinc-700 dark:text-zinc-300">
                  App Name
                </label>
                <input
                  type="text"
                  value={customName}
                  onChange={(e) => setCustomName(e.target.value)}
                  placeholder="e.g. Signal"
                  className="w-full mt-1 p-2.5 rounded-xl border border-zinc-200 dark:border-zinc-700 bg-zinc-50 dark:bg-zinc-800 text-xs text-zinc-900 dark:text-zinc-100 focus:outline-none focus:ring-2 focus:ring-[#315e63]"
                />
              </div>
              <div>
                <label className="text-[11px] font-medium text-zinc-700 dark:text-zinc-300">
                  Package Name
                </label>
                <input
                  type="text"
                  value={customPackage}
                  onChange={(e) => setCustomPackage(e.target.value)}
                  placeholder="org.thoughtcrime.securesms"
                  className="w-full mt-1 p-2.5 rounded-xl border border-zinc-200 dark:border-zinc-700 bg-zinc-50 dark:bg-zinc-800 text-xs font-mono text-zinc-900 dark:text-zinc-100 focus:outline-none focus:ring-2 focus:ring-[#315e63]"
                />
              </div>
              <div className="flex justify-end gap-2 pt-2">
                <button
                  type="button"
                  onClick={() => setIsAddCustomOpen(false)}
                  className="px-3.5 py-2 rounded-xl text-xs font-medium text-zinc-600 dark:text-zinc-400 hover:bg-zinc-100 dark:hover:bg-zinc-800"
                >
                  Cancel
                </button>
                <button
                  type="submit"
                  disabled={!customName.trim() || !customPackage.trim()}
                  className="px-4 py-2 rounded-xl text-xs font-semibold bg-[#315e63] dark:bg-[#78aeb3] text-white dark:text-zinc-950 disabled:opacity-40"
                >
                  Clone into Sandbox
                </button>
              </div>
            </form>
          </div>
        </div>
      )}

      {/* Modal: Launched Cloned App Sandbox View */}
      {activeApp && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/75 backdrop-blur-xs p-4">
          <div className="w-full max-w-md bg-white dark:bg-[#172021] rounded-3xl shadow-2xl border border-zinc-200 dark:border-zinc-800 flex flex-col max-h-[85vh] overflow-hidden">
            {/* Header */}
            <div className="p-4 border-b border-zinc-200 dark:border-zinc-800 flex items-center justify-between bg-zinc-50 dark:bg-zinc-900">
              <div className="flex items-center gap-2.5">
                <div
                  className="w-7 h-7 rounded-lg flex items-center justify-center text-white font-bold text-xs"
                  style={{ backgroundColor: activeApp.iconColor }}
                >
                  {activeApp.name.slice(0, 1)}
                </div>
                <div>
                  <h4 className="text-xs font-bold text-zinc-900 dark:text-zinc-100 flex items-center gap-1.5">
                    <span>{activeApp.name}</span>
                    <span className="text-[10px] font-normal text-emerald-600 dark:text-emerald-400 font-mono">
                      (Isolated UID {state.profileUserId})
                    </span>
                  </h4>
                  <p className="text-[10px] text-zinc-400 font-mono">
                    {activeApp.packageName}
                  </p>
                </div>
              </div>

              <div className="flex items-center gap-1">
                <button
                  onClick={onLock}
                  title="Panic lock now"
                  className="p-1.5 text-zinc-400 hover:text-rose-500 rounded-lg hover:bg-zinc-200 dark:hover:bg-zinc-800"
                >
                  <Lock className="w-4 h-4" />
                </button>
                <button
                  onClick={() => setActiveApp(null)}
                  className="text-xs px-2.5 py-1 rounded-lg bg-zinc-200 dark:bg-zinc-800 text-zinc-700 dark:text-zinc-300 font-medium hover:bg-zinc-300"
                >
                  Close
                </button>
              </div>
            </div>

            {/* Sandbox Workspace Body */}
            <div className="p-4 flex-1 overflow-y-auto space-y-4">
              <div className="p-3 rounded-xl bg-zinc-100 dark:bg-zinc-800/60 border border-zinc-200/60 dark:border-zinc-700/60 text-xs space-y-1">
                <div className="flex justify-between font-mono text-[11px] text-zinc-500">
                  <span>Data Isolation:</span>
                  <span className="text-emerald-600 dark:text-emerald-400 font-semibold">
                    /data/user/{state.profileUserId}/{activeApp.packageName}
                  </span>
                </div>
                <div className="flex justify-between font-mono text-[11px] text-zinc-500">
                  <span>Google Play Services:</span>
                  <span className="text-zinc-700 dark:text-zinc-300">Bound to Sandbox UID</span>
                </div>
                <div className="flex justify-between font-mono text-[11px] text-zinc-500">
                  <span>Signature Integrity:</span>
                  <span className="text-emerald-600 dark:text-emerald-400">Match (Original APK)</span>
                </div>
              </div>

              <div className="space-y-2">
                <label className="text-xs font-semibold text-zinc-800 dark:text-zinc-200 flex items-center justify-between">
                  <span>Clone App Media / Message Content</span>
                  <span className="text-[10px] text-zinc-400 font-normal">
                    Isolated local session
                  </span>
                </label>
                <textarea
                  rows={4}
                  value={mockContent}
                  onChange={(e) => setMockContent(e.target.value)}
                  placeholder={`Write note, draft, or chat export from ${activeApp.name} to store directly into the encrypted vault...`}
                  className="w-full p-3 rounded-xl border border-zinc-200 dark:border-zinc-700 bg-zinc-50 dark:bg-zinc-950 text-xs text-zinc-900 dark:text-zinc-100 focus:outline-none focus:ring-2 focus:ring-[#315e63]"
                />
              </div>

              <div className="p-3 rounded-xl bg-amber-50 dark:bg-amber-950/40 border border-amber-200/80 dark:border-amber-900/60 text-[11px] text-amber-800 dark:text-amber-200 flex items-start gap-2">
                <FolderLock className="w-4 h-4 shrink-0 mt-0.5 text-amber-600" />
                <span>
                  <strong>Vault Ingestion:</strong> Ingesting files from this cloned app bypasses the
                  Android Public Gallery, protecting against casual gallery snooping.
                </span>
              </div>
            </div>

            {/* Footer */}
            <div className="p-4 border-t border-zinc-200 dark:border-zinc-800 bg-zinc-50 dark:bg-zinc-900 flex justify-between items-center">
              <span className="text-[11px] text-zinc-400">
                Panic triggers freeze this space immediately.
              </span>
              <button
                type="button"
                onClick={handleSaveToVault}
                disabled={!mockContent.trim() || isSavingToVault}
                className="flex items-center gap-1.5 px-4 py-2 rounded-xl bg-[#315e63] dark:bg-[#78aeb3] text-white dark:text-zinc-950 text-xs font-bold hover:opacity-90 disabled:opacity-40 transition-opacity"
              >
                <FolderLock className="w-4 h-4" />
                <span>{isSavingToVault ? 'Encrypting...' : 'Save into Vault'}</span>
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
};
