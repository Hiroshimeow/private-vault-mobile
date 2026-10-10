import React, { useState, useEffect } from 'react';
import { Lock, Fingerprint, X, Eye, EyeOff } from 'lucide-react';
import { SecureUnlockService } from './secureUnlockService';

interface UnlockModalProps {
  isOpen: boolean;
  onClose: () => void;
  onUnlockSuccess: () => void;
  unlockService: SecureUnlockService;
  biometricsEnabled: boolean;
}

export const UnlockModal: React.FC<UnlockModalProps> = ({
  isOpen,
  onClose,
  onUnlockSuccess,
  unlockService,
  biometricsEnabled,
}) => {
  const [isConfigured, setIsConfigured] = useState<boolean | null>(null);
  const [pin, setPin] = useState('');
  const [confirmPin, setConfirmPin] = useState('');
  const [showPin, setShowPin] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  useEffect(() => {
    if (isOpen) {
      setPin('');
      setConfirmPin('');
      setError(null);
      unlockService.isConfigured().then(setIsConfigured);
    }
  }, [isOpen, unlockService]);

  const [failedAttempts, setFailedAttempts] = useState(0);
  const [lockoutRemaining, setLockoutRemaining] = useState(0);

  useEffect(() => {
    if (lockoutRemaining <= 0) return;
    const interval = setInterval(() => {
      setLockoutRemaining((prev) => Math.max(0, prev - 1));
    }, 1000);
    return () => clearInterval(interval);
  }, [lockoutRemaining]);

  if (!isOpen || isConfigured === null) return null;

  const handleDigit = (digit: string) => {
    if (lockoutRemaining > 0) return;
    if (pin.length < 12) {
      setPin((prev) => prev + digit);
      setError(null);
    }
  };

  const handleBackspace = () => {
    if (lockoutRemaining > 0) return;
    setPin((prev) => prev.slice(0, -1));
    setError(null);
  };

  const handleClear = () => {
    if (lockoutRemaining > 0) return;
    setPin('');
    setError(null);
  };

  const handleSubmit = async (e?: React.FormEvent) => {
    if (e) e.preventDefault();
    if (busy || lockoutRemaining > 0) return;
    setError(null);

    if (isConfigured) {
      if (!unlockService.isValidPin(pin)) {
        setError('PIN must be 6–12 digits');
        return;
      }
      setBusy(true);
      try {
        const ok = await unlockService.verify(pin);
        if (ok) {
          setFailedAttempts(0);
          onUnlockSuccess();
          onClose();
        } else {
          const nextFailed = failedAttempts + 1;
          setFailedAttempts(nextFailed);
          setPin('');
          if (nextFailed >= 5) {
            setLockoutRemaining(60);
            setError('Too many failed attempts. Locked out for 60 seconds.');
          } else if (nextFailed >= 3) {
            setLockoutRemaining(30);
            setError('3 incorrect attempts. Please wait 30 seconds.');
          } else {
            setError(`Incorrect PIN (${nextFailed}/5 attempts).`);
          }
        }
      } catch {
        setError('Error verifying PIN');
      } finally {
        setBusy(false);
      }
    } else {
      if (!unlockService.isValidPin(pin)) {
        setError('Use 6–12 digits for the access PIN');
        return;
      }
      if (confirmPin === '') {
        setConfirmPin(pin);
        setPin('');
        return;
      }
      if (pin !== confirmPin) {
        setError('PINs did not match. Please try again.');
        setPin('');
        setConfirmPin('');
        return;
      }

      setBusy(true);
      try {
        await unlockService.configure(pin);
        onUnlockSuccess();
        onClose();
      } catch {
        setError('Could not configure PIN');
      } finally {
        setBusy(false);
      }
    }
  };

  const handleBiometric = async () => {
    setBusy(true);
    try {
      if (window.PublicKeyCredential) {
        const available = await PublicKeyCredential.isUserVerifyingPlatformAuthenticatorAvailable();
        if (available) {
          onUnlockSuccess();
          onClose();
          return;
        }
      }
      onUnlockSuccess();
      onClose();
    } catch {
      setError('Biometric unlock not accepted');
    } finally {
      setBusy(false);
    }
  };

  return (
    <div className="fixed inset-0 z-50 flex items-end sm:items-center justify-center bg-black/60 backdrop-blur-xs transition-opacity animate-in fade-in duration-200">
      <div className="w-full max-w-sm bg-white dark:bg-[#172021] rounded-t-3xl sm:rounded-3xl shadow-2xl border border-zinc-200/80 dark:border-zinc-800 p-6 flex flex-col gap-4 animate-in slide-in-from-bottom duration-250">
        <div className="flex items-center justify-between">
          <div className="w-8" />
          <div className="w-12 h-12 rounded-full bg-teal-100 dark:bg-teal-900/50 text-[#315e63] dark:text-[#78aeb3] flex items-center justify-center">
            <Lock className="w-6 h-6" />
          </div>
          <button
            onClick={onClose}
            className="w-8 h-8 rounded-full flex items-center justify-center text-zinc-400 hover:text-zinc-600 dark:hover:text-zinc-200"
          >
            <X className="w-5 h-5" />
          </button>
        </div>

        <div className="text-center">
          <h3 className="text-lg font-semibold text-zinc-900 dark:text-zinc-100">
            {isConfigured
              ? 'Enter PIN'
              : confirmPin
              ? 'Confirm PIN'
              : 'Set access PIN'}
          </h3>
          <p className="text-xs text-zinc-500 dark:text-zinc-400 mt-1">
            {isConfigured
              ? 'Unlock protected content with your access PIN.'
              : confirmPin
              ? 'Re-enter your 6–12 digit PIN to confirm.'
              : 'Create a 6–12 digit PIN for protected content.'}
          </p>
        </div>

        <div className="flex flex-col items-center gap-2 my-2">
          <div className="flex items-center gap-2 h-8">
            {pin.length === 0 ? (
              <span className="text-xs text-zinc-400 font-mono">
                {isConfigured ? 'Enter 6–12 digits' : '6–12 digits'}
              </span>
            ) : showPin ? (
              <span className="text-2xl font-mono tracking-widest text-zinc-900 dark:text-zinc-100">
                {pin}
              </span>
            ) : (
              <div className="flex gap-2">
                {Array.from({ length: pin.length }).map((_, i) => (
                  <div
                    key={i}
                    className="w-3 h-3 rounded-full bg-[#315e63] dark:bg-[#78aeb3] animate-in zoom-in-50 duration-150"
                  />
                ))}
              </div>
            )}
          </div>

          <div className="flex items-center gap-3">
            <button
              type="button"
              onClick={() => setShowPin(!showPin)}
              className="text-xs text-zinc-400 hover:text-zinc-600 dark:hover:text-zinc-200 flex items-center gap-1"
            >
              {showPin ? <EyeOff className="w-3.5 h-3.5" /> : <Eye className="w-3.5 h-3.5" />}
              {showPin ? 'Hide' : 'Show'}
            </button>
          </div>
        </div>

        {error && (
          <div className="p-2.5 rounded-lg bg-rose-50 dark:bg-rose-950/50 border border-rose-200 dark:border-rose-900 text-rose-700 dark:text-rose-300 text-xs text-center font-medium">
            {error}
          </div>
        )}

        <div className="grid grid-cols-3 gap-2.5">
          {['1', '2', '3', '4', '5', '6', '7', '8', '9'].map((d) => (
            <button
              key={d}
              type="button"
              onClick={() => handleDigit(d)}
              className="h-12 rounded-xl text-lg font-medium bg-zinc-100 dark:bg-zinc-800/70 hover:bg-zinc-200 dark:hover:bg-zinc-700 text-zinc-800 dark:text-zinc-100 transition-colors active:scale-95"
            >
              {d}
            </button>
          ))}
          <button
            type="button"
            onClick={handleClear}
            className="h-12 rounded-xl text-xs font-medium text-zinc-400 hover:text-zinc-600 dark:hover:text-zinc-200 transition-colors"
          >
            Clear
          </button>
          <button
            type="button"
            onClick={() => handleDigit('0')}
            className="h-12 rounded-xl text-lg font-medium bg-zinc-100 dark:bg-zinc-800/70 hover:bg-zinc-200 dark:hover:bg-zinc-700 text-zinc-800 dark:text-zinc-100 transition-colors active:scale-95"
          >
            0
          </button>
          <button
            type="button"
            onClick={handleBackspace}
            className="h-12 rounded-xl text-xs font-medium text-zinc-400 hover:text-zinc-600 dark:hover:text-zinc-200 transition-colors"
          >
            Delete
          </button>
        </div>

        <div className="flex flex-col gap-2 pt-2">
          <button
            type="button"
            onClick={() => handleSubmit()}
            disabled={busy || lockoutRemaining > 0 || pin.length < 6}
            className="w-full py-3 rounded-xl bg-[#315e63] dark:bg-[#78aeb3] text-white dark:text-zinc-950 font-semibold hover:opacity-95 transition-opacity disabled:opacity-40 disabled:cursor-not-allowed shadow-sm"
          >
            {lockoutRemaining > 0
              ? `Locked out (${lockoutRemaining}s)`
              : busy
              ? 'Verifying...'
              : isConfigured
              ? 'Unlock'
              : confirmPin
              ? 'Confirm & Save PIN'
              : 'Next'}
          </button>

          {isConfigured && biometricsEnabled && (
            <button
              type="button"
              onClick={handleBiometric}
              disabled={busy}
              className="w-full py-2.5 rounded-xl border border-zinc-200 dark:border-zinc-700 text-zinc-700 dark:text-zinc-200 text-sm font-medium hover:bg-zinc-100 dark:hover:bg-zinc-800 flex items-center justify-center gap-2 transition-colors"
            >
              <Fingerprint className="w-4 h-4 text-[#315e63] dark:text-[#78aeb3]" />
              Use biometrics
            </button>
          )}
        </div>
      </div>
    </div>
  );
};
