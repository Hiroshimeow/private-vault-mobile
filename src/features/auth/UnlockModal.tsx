import React, { useState, useEffect } from 'react';
import { Lock, Fingerprint, X, Eye, EyeOff } from 'lucide-react';
import { SecureUnlockService } from './secureUnlockService';

interface UnlockModalProps {
  isOpen: boolean;
  onClose: () => void;
  onUnlockSuccess: (isDecoy?: boolean) => void;
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
  const [lockoutRemaining, setLockoutRemaining] = useState(0);

  useEffect(() => {
    if (isOpen) {
      setPin('');
      setConfirmPin('');
      setError(null);
      unlockService.isConfigured().then(setIsConfigured);
      unlockService.getLockoutStatus().then((status) => {
        if (status.isLocked) {
          setLockoutRemaining(status.remainingSeconds);
        }
      });
    }
  }, [isOpen, unlockService]);

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
        setError('Mã PIN phải từ 4 đến 12 chữ số');
        return;
      }
      setBusy(true);
      try {
        const res = await unlockService.unlock(pin);
        if (res.success) {
          onUnlockSuccess(res.isDecoy);
          onClose();
        } else {
          setPin('');
          if (res.lockoutSeconds && res.lockoutSeconds > 0) {
            setLockoutRemaining(res.lockoutSeconds);
            setError(`Quá nhiều lần nhập sai. Bị tạm khóa trong ${res.lockoutSeconds} giây.`);
          } else {
            setError('Mã PIN không chính xác. Vui lòng thử lại.');
          }
        }
      } catch {
        setError('Lỗi khi xác thực mã PIN');
      } finally {
        setBusy(false);
      }
    } else {
      if (!unlockService.isValidPin(pin)) {
        setError('Mã PIN thiết lập phải từ 4 đến 12 chữ số');
        return;
      }
      if (confirmPin === '') {
        setConfirmPin(pin);
        setPin('');
        return;
      }
      if (pin !== confirmPin) {
        setError('Mã PIN xác nhận không khớp. Vui lòng nhập lại.');
        setPin('');
        setConfirmPin('');
        return;
      }

      setBusy(true);
      try {
        await unlockService.configure(pin);
        onUnlockSuccess(false);
        onClose();
      } catch {
        setError('Không thể thiết lập mã PIN và tạo khóa');
      } finally {
        setBusy(false);
      }
    }
  };

  /**
   * Biometric authentication: strictly fail-closed.
   * Unsupported, canceled, or failed biometric MUST NEVER unlock.
   */
  const handleBiometric = async () => {
    if (busy || lockoutRemaining > 0) return;
    setBusy(true);
    setError(null);
    try {
      if (!window.PublicKeyCredential) {
        setError('Thiết bị không hỗ trợ xác thực sinh trắc học web.');
        return;
      }
      const available = await PublicKeyCredential.isUserVerifyingPlatformAuthenticatorAvailable();
      if (!available) {
        setError('Cảm biến sinh trắc học không khả dụng trên thiết bị này.');
        return;
      }
      // Fail-closed requirement: WebAuthn requires credential registration and challenge assertion.
      // Without provisioned credentials or on cancellation, maintain lock.
      setError('Cần cấu hình vân tay hệ điều hành cho ứng dụng. Vui lòng sử dụng mã PIN.');
    } catch {
      setError('Xác thực sinh trắc học bị hủy hoặc gặp lỗi.');
    } finally {
      setBusy(false);
    }
  };

  return (
    <div className="fixed inset-0 z-50 flex items-end sm:items-center justify-center bg-black/60 backdrop-blur-xs transition-opacity">
      <div className="w-full max-w-sm bg-white dark:bg-[#172021] rounded-t-3xl sm:rounded-3xl shadow-2xl border border-zinc-200/80 dark:border-zinc-800 p-6 flex flex-col gap-4">
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
              ? 'Nhập mã PIN'
              : confirmPin
              ? 'Xác nhận mã PIN'
              : 'Thiết lập mã PIN'}
          </h3>
          <p className="text-xs text-zinc-500 dark:text-zinc-400 mt-1">
            {isConfigured
              ? 'Mở khóa không gian bảo mật bằng mã PIN của bạn.'
              : confirmPin
              ? 'Nhập lại mã PIN để xác nhận.'
              : 'Tạo mã PIN 4–12 chữ số để bảo vệ kho dữ liệu.'}
          </p>
        </div>

        <div className="flex flex-col items-center gap-2 my-2">
          <div className="flex items-center gap-2 h-8">
            {pin.length === 0 ? (
              <span className="text-xs text-zinc-400 font-mono">
                {isConfigured ? 'Nhập 4–12 chữ số' : '4–12 chữ số'}
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
                    className="w-3 h-3 rounded-full bg-[#315e63] dark:bg-[#78aeb3]"
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
              {showPin ? 'Ẩn' : 'Hiện'}
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
            Xóa
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
            Lùi
          </button>
        </div>

        <div className="flex flex-col gap-2 pt-2">
          <button
            type="button"
            onClick={() => handleSubmit()}
            disabled={busy || lockoutRemaining > 0 || pin.length < 4}
            className="w-full py-3 rounded-xl bg-[#315e63] dark:bg-[#78aeb3] text-white dark:text-zinc-950 font-semibold hover:opacity-95 transition-opacity disabled:opacity-40 disabled:cursor-not-allowed shadow-sm"
          >
            {lockoutRemaining > 0
              ? `Tạm khóa (${lockoutRemaining}s)`
              : busy
              ? 'Đang kiểm tra...'
              : isConfigured
              ? 'Mở khóa'
              : confirmPin
              ? 'Xác nhận & Lưu PIN'
              : 'Tiếp tục'}
          </button>

          {isConfigured && biometricsEnabled && (
            <button
              type="button"
              onClick={handleBiometric}
              disabled={busy || lockoutRemaining > 0}
              className="w-full py-2.5 rounded-xl border border-zinc-200 dark:border-zinc-700 text-zinc-700 dark:text-zinc-200 text-sm font-medium hover:bg-zinc-100 dark:hover:bg-zinc-800 flex items-center justify-center gap-2 transition-colors disabled:opacity-40"
            >
              <Fingerprint className="w-4 h-4 text-[#315e63] dark:text-[#78aeb3]" />
              Sử dụng sinh trắc học
            </button>
          )}
        </div>
      </div>
    </div>
  );
};
