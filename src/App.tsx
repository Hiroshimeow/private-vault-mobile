import React, { useState, useEffect, useMemo, useRef } from 'react';
import { LockController } from './features/auth/lockController';
import { SecureUnlockService } from './features/auth/secureUnlockService';
import { LocalVaultRepository } from './features/vault/vaultRepository';
import { AppSettingsStore } from './features/settings/appSettings';
import { PanicSensorService } from './features/panic/panicSensorService';
import { AppSettings } from './types';
import { CalculatorCover } from './features/cover/CalculatorCover';
import { NotesCover } from './features/cover/NotesCover';
import { SecretWorkspace } from './features/vault/SecretWorkspace';
import { UnlockModal } from './features/auth/UnlockModal';

export const App: React.FC = () => {
  const lockController = useMemo(() => new LockController(), []);
  const unlockService = useMemo(() => new SecureUnlockService(), []);
  const vaultRepository = useMemo(() => new LocalVaultRepository(), []);
  const settingsStore = useMemo(() => new AppSettingsStore(), []);

  const [settings, setSettings] = useState<AppSettings>(() => settingsStore.load());
  const [isLocked, setIsLocked] = useState(lockController.isLocked);
  const [isUnlockModalOpen, setIsUnlockModalOpen] = useState(false);

  const panicSensorRef = useRef<PanicSensorService | null>(null);

  useEffect(() => {
    if (settings.darkMode) {
      document.documentElement.classList.add('dark');
    } else {
      document.documentElement.classList.remove('dark');
    }
  }, [settings.darkMode]);

  useEffect(() => {
    const unsubscribe = lockController.subscribe(() => {
      setIsLocked(lockController.isLocked);
    });
    return () => {
      unsubscribe();
      lockController.dispose();
    };
  }, [lockController]);

  useEffect(() => {
    const panic = new PanicSensorService(lockController, settings);
    panic.start();
    panicSensorRef.current = panic;

    return () => {
      panic.dispose();
      panicSensorRef.current = null;
    };
  }, [lockController, settings]);

  useEffect(() => {
    if (settings.lockDisabled) {
      lockController.setLockDisabled(true);
    } else {
      lockController.setLockDisabled(false);
    }
  }, [settings.lockDisabled, lockController]);

  useEffect(() => {
    const handleSuspend = (e: Event) => {
      const customEvent = e as CustomEvent<boolean>;
      lockController.suspendLock(customEvent.detail !== false);
    };
    const handleWindowFocus = () => {
      // Grace period when returning to app from system picker / camera
      setTimeout(() => {
        lockController.suspendLock(false);
      }, 1000);
    };

    window.addEventListener('vault-suspend-lock', handleSuspend);
    window.addEventListener('focus', handleWindowFocus);

    return () => {
      window.removeEventListener('vault-suspend-lock', handleSuspend);
      window.removeEventListener('focus', handleWindowFocus);
    };
  }, [lockController]);

  useEffect(() => {
    const handleVisibilityChange = () => {
      if (document.hidden) {
        lockController.onBackground(settings.autoLockSeconds * 1000);
      } else {
        lockController.onForeground();
      }
    };

    document.addEventListener('visibilitychange', handleVisibilityChange);
    return () => {
      document.removeEventListener('visibilitychange', handleVisibilityChange);
    };
  }, [lockController, settings.autoLockSeconds]);

  const handleSettingsChanged = (next: AppSettings) => {
    setSettings(next);
    settingsStore.save(next);
    lockController.setLockDisabled(Boolean(next.lockDisabled));
    if (panicSensorRef.current) {
      panicSensorRef.current.updateSettings(next);
    }
  };

  const handleResetPin = async () => {
    await unlockService.reset();
    lockController.lock(true);
    setIsUnlockModalOpen(true);
  };

  const handleAttemptPin = async (candidate: string): Promise<boolean> => {
    try {
      const result = await unlockService.unlock(candidate);
      if (result.success) {
        if (result.isDecoy) {
          // Decoy PIN entered
          return false;
        }
        lockController.unlock();
        return true;
      }
      return false;
    } catch (err) {
      console.error('Error verifying PIN:', err);
      return false;
    }
  };

  const handleManualLock = () => {
    if (settings.lockDisabled) {
      // If user manually taps Lock while in disabled lock mode, turn lock back on
      const nextSettings = { ...settings, lockDisabled: false };
      handleSettingsChanged(nextSettings);
    }
    lockController.lock(true);
  };

  return (
    <div className="h-screen w-screen min-h-dvh bg-zinc-100 dark:bg-[#101718] flex flex-col overflow-hidden font-sans">
      <div className="w-full h-full bg-white dark:bg-[#101718] flex flex-col relative overflow-hidden">
        {isLocked ? (
          settings.cover === 'notes' ? (
            <NotesCover
              onUnlockRequested={() => setIsUnlockModalOpen(true)}
              onAttemptPin={handleAttemptPin}
            />
          ) : (
            <CalculatorCover
              onUnlockRequested={() => setIsUnlockModalOpen(true)}
              onAttemptPin={handleAttemptPin}
            />
          )
        ) : (
          <SecretWorkspace
            onLock={handleManualLock}
            settings={settings}
            onSettingsChanged={handleSettingsChanged}
            vaultRepository={vaultRepository}
            onTriggerPanic={() => lockController.panic()}
            onResetPin={handleResetPin}
          />
        )}

        <UnlockModal
          isOpen={isUnlockModalOpen}
          onClose={() => setIsUnlockModalOpen(false)}
          onUnlockSuccess={(isDecoy) => {
            if (isDecoy) {
              // Decoy PIN entered: keep real vault locked or route to decoy
              setIsUnlockModalOpen(false);
              return;
            }
            lockController.unlock();
            setIsUnlockModalOpen(false);
          }}
          unlockService={unlockService}
          biometricsEnabled={settings.biometricsEnabled}
        />
      </div>
    </div>
  );
};

export default App;
