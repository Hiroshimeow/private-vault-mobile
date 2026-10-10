import React from 'react';
import {
  Layers,
  EyeOff,
  Fingerprint,
  Shield,
  Moon,
  AppWindow,
  KeyRound,
  Zap,
} from 'lucide-react';
import { AppSettings } from '../../types';

interface SettingsHomeProps {
  settings: AppSettings;
  onSettingsChanged: (next: AppSettings) => void;
  onTriggerPanic: () => void;
  onResetPin: () => void;
}

export const SettingsHome: React.FC<SettingsHomeProps> = ({
  settings,
  onSettingsChanged,
  onTriggerPanic,
  onResetPin,
}) => {
  const update = (partial: Partial<AppSettings>) => {
    onSettingsChanged({ ...settings, ...partial });
  };

  return (
    <div className="flex flex-col h-full bg-zinc-50 dark:bg-[#101718] overflow-y-auto p-4 pb-12 space-y-4">
      {/* Tạm thời bỏ khóa / Chế độ app thông thường */}
      <div className="rounded-2xl bg-white dark:bg-[#172021] border border-zinc-200/80 dark:border-zinc-800/80 p-4 shadow-xs space-y-3">
        <div className="flex items-center justify-between">
          <div className="flex items-center gap-2">
            <AppWindow className="w-4 h-4 text-teal-400" />
            <h3 className="text-sm font-semibold text-zinc-900 dark:text-zinc-100">
              Tạm thời bỏ khóa (Chế độ App thông thường)
            </h3>
          </div>
          <input
            type="checkbox"
            checked={Boolean(settings.lockDisabled)}
            onChange={(e) => update({ lockDisabled: e.target.checked })}
            className="w-4 h-4 accent-teal-500 cursor-pointer"
          />
        </div>
        <p className="text-xs text-zinc-500 dark:text-zinc-400 leading-relaxed">
          Khi bật, app trở thành ứng dụng thông thường: ấn vào là mở thẳng vào Thư mục Bảo mật mà không cần nhập PIN hay ngụy trang máy tính. Bạn có thể bấm nút <strong>Khóa</strong> trên thanh tiêu đề để kích hoạt khóa lại bất cứ lúc nào.
        </p>
        <div className="p-2.5 rounded-xl bg-teal-950/30 border border-teal-800/40 text-[11px] text-teal-300">
          💡 <em>Mẹo:</em> Khi đang ở màn hình Máy tính ngụy trang, bạn cũng có thể gõ trực tiếp mật khẩu (ví dụ: <code>1111</code>) rồi bấm <code>=</code> để mở khóa ngay lập tức.
        </div>
      </div>

      <div className="rounded-2xl bg-white dark:bg-[#172021] border border-zinc-200/80 dark:border-zinc-800/80 p-4 shadow-xs">
        <div className="flex items-center gap-2 mb-3">
          <Layers className="w-4 h-4 text-[#315e63] dark:text-[#78aeb3]" />
          <h3 className="text-sm font-semibold text-zinc-900 dark:text-zinc-100">Cover</h3>
        </div>
        <p className="text-xs text-zinc-500 dark:text-zinc-400 mb-3">
          Default disguise app shown when locked.
        </p>
        <div className="grid grid-cols-2 gap-2 p-1 bg-zinc-100 dark:bg-zinc-800/80 rounded-xl">
          <button
            type="button"
            onClick={() => update({ cover: 'calculator' })}
            className={`py-2 rounded-lg text-xs font-semibold transition-all ${
              settings.cover === 'calculator'
                ? 'bg-white dark:bg-zinc-900 text-zinc-900 dark:text-zinc-100 shadow-xs'
                : 'text-zinc-500 hover:text-zinc-800 dark:hover:text-zinc-200'
            }`}
          >
            Calculator
          </button>
          <button
            type="button"
            onClick={() => update({ cover: 'notes' })}
            className={`py-2 rounded-lg text-xs font-semibold transition-all ${
              settings.cover === 'notes'
                ? 'bg-white dark:bg-zinc-900 text-zinc-900 dark:text-zinc-100 shadow-xs'
                : 'text-zinc-500 hover:text-zinc-800 dark:hover:text-zinc-200'
            }`}
          >
            Notes
          </button>
        </div>
      </div>

      <div className="rounded-2xl bg-white dark:bg-[#172021] border border-zinc-200/80 dark:border-zinc-800/80 p-4 shadow-xs space-y-4">
        <div className="flex items-center justify-between">
          <div className="flex items-center gap-2">
            <EyeOff className="w-4 h-4 text-[#315e63] dark:text-[#78aeb3]" />
            <h3 className="text-sm font-semibold text-zinc-900 dark:text-zinc-100">
              Concealment
            </h3>
          </div>
          <button
            type="button"
            onClick={onTriggerPanic}
            className="flex items-center gap-1 px-2.5 py-1 rounded-lg bg-rose-50 dark:bg-rose-950/60 text-rose-700 dark:text-rose-300 border border-rose-200 dark:border-rose-900 text-[11px] font-medium hover:bg-rose-100"
            title="Test instant panic conceal"
          >
            <Zap className="w-3 h-3" />
            <span>Test Panic</span>
          </button>
        </div>

        <div className="flex items-center justify-between">
          <div>
            <div className="text-xs font-medium text-zinc-800 dark:text-zinc-200">
              Shake to conceal
            </div>
            <div className="text-[11px] text-zinc-400">
              Locks and returns to the cover workspace immediately.
            </div>
          </div>
          <input
            type="checkbox"
            checked={settings.panicShakeEnabled}
            onChange={(e) => update({ panicShakeEnabled: e.target.checked })}
            className="w-4 h-4 accent-[#315e63]"
          />
        </div>

        {settings.panicShakeEnabled && (
          <div className="space-y-1 pt-1">
            <div className="flex justify-between text-xs text-zinc-500">
              <span>Shake sensitivity</span>
              <span className="font-mono">{settings.shakeThresholdG.toFixed(1)} G</span>
            </div>
            <input
              type="range"
              min="1.5"
              max="4.5"
              step="0.1"
              value={settings.shakeThresholdG}
              onChange={(e) => update({ shakeThresholdG: parseFloat(e.target.value) })}
              className="w-full accent-[#315e63]"
            />
          </div>
        )}

        <hr className="border-zinc-100 dark:border-zinc-800" />

        <div className="flex items-center justify-between">
          <div>
            <div className="text-xs font-medium text-zinc-800 dark:text-zinc-200">
              Face-down conceal
            </div>
            <div className="text-[11px] text-zinc-400">
              Locks after phone stays face-down for the configured delay.
            </div>
          </div>
          <input
            type="checkbox"
            checked={settings.panicFaceDownEnabled}
            onChange={(e) => update({ panicFaceDownEnabled: e.target.checked })}
            className="w-4 h-4 accent-[#315e63]"
          />
        </div>

        {settings.panicFaceDownEnabled && (
          <div className="space-y-1 pt-1">
            <div className="flex justify-between text-xs text-zinc-500">
              <span>Face-down delay</span>
              <span className="font-mono">{(settings.faceDownDelayMs / 1000).toFixed(1)} s</span>
            </div>
            <input
              type="range"
              min="500"
              max="3000"
              step="250"
              value={settings.faceDownDelayMs}
              onChange={(e) => update({ faceDownDelayMs: parseInt(e.target.value, 10) })}
              className="w-full accent-[#315e63]"
            />
          </div>
        )}

        <hr className="border-zinc-100 dark:border-zinc-800" />

        <div className="flex items-center justify-between">
          <div>
            <div className="text-xs font-medium text-zinc-800 dark:text-zinc-200">
              Lock after background
            </div>
            <div className="text-[11px] text-zinc-400">
              Locks when switching tabs or exiting the app.
            </div>
          </div>
          <select
            value={settings.autoLockSeconds}
            onChange={(e) => update({ autoLockSeconds: parseInt(e.target.value, 10) })}
            className="text-xs rounded-lg bg-zinc-100 dark:bg-zinc-800 border border-zinc-200 dark:border-zinc-700 px-2.5 py-1.5 text-zinc-800 dark:text-zinc-200 cursor-pointer"
          >
            <option value={0}>Immediately</option>
            <option value={15}>15 seconds</option>
            <option value={30}>30 seconds</option>
            <option value={60}>1 minute</option>
            <option value={300}>5 minutes</option>
          </select>
        </div>
      </div>

      <div className="rounded-2xl bg-white dark:bg-[#172021] border border-zinc-200/80 dark:border-zinc-800/80 p-4 shadow-xs space-y-3">
        <div className="flex items-center gap-2">
          <Fingerprint className="w-4 h-4 text-[#315e63] dark:text-[#78aeb3]" />
          <h3 className="text-sm font-semibold text-zinc-900 dark:text-zinc-100">Access</h3>
        </div>

        <div className="flex items-center justify-between">
          <div>
            <div className="text-xs font-medium text-zinc-800 dark:text-zinc-200">
              Biometric unlock
            </div>
            <div className="text-[11px] text-zinc-400">
              PIN remains the fallback and key owner.
            </div>
          </div>
          <input
            type="checkbox"
            checked={settings.biometricsEnabled}
            onChange={(e) => update({ biometricsEnabled: e.target.checked })}
            className="w-4 h-4 accent-[#315e63]"
          />
        </div>

        <button
          type="button"
          onClick={onResetPin}
          className="w-full mt-2 py-2 rounded-xl border border-zinc-200 dark:border-zinc-700 text-xs font-medium text-zinc-700 dark:text-zinc-300 hover:bg-zinc-100 dark:hover:bg-zinc-800 flex items-center justify-center gap-1.5 transition-colors"
        >
          <KeyRound className="w-3.5 h-3.5" />
          <span>Reset or change access PIN</span>
        </button>
      </div>

      <div className="rounded-2xl bg-white dark:bg-[#172021] border border-zinc-200/80 dark:border-zinc-800/80 p-4 shadow-xs space-y-3">
        <div className="flex items-center gap-2">
          <Shield className="w-4 h-4 text-[#315e63] dark:text-[#78aeb3]" />
          <h3 className="text-sm font-semibold text-zinc-900 dark:text-zinc-100">
            Data Handling
          </h3>
        </div>

        <div className="flex items-center justify-between">
          <div>
            <div className="text-xs font-medium text-zinc-800 dark:text-zinc-200">
              Clear browser data on close
            </div>
            <div className="text-[11px] text-zinc-400">
              Purges ephemeral session stores on app exit.
            </div>
          </div>
          <input
            type="checkbox"
            checked={settings.browserClearOnClose}
            onChange={(e) => update({ browserClearOnClose: e.target.checked })}
            className="w-4 h-4 accent-[#315e63]"
          />
        </div>

        <hr className="border-zinc-100 dark:border-zinc-800" />

        <div className="flex items-center justify-between">
          <div>
            <div className="text-xs font-medium text-zinc-800 dark:text-zinc-200">
              Confirm before export
            </div>
            <div className="text-[11px] text-zinc-400">
              Warn before saving items to external device storage.
            </div>
          </div>
          <input
            type="checkbox"
            checked={settings.confirmExport}
            onChange={(e) => update({ confirmExport: e.target.checked })}
            className="w-4 h-4 accent-[#315e63]"
          />
        </div>

        <div className="p-2.5 rounded-xl bg-teal-950/30 border border-teal-800/40 text-[11px] text-teal-300 leading-relaxed">
          ✓ <strong>Chính sách lưu trữ tệp:</strong> Khi nạp ảnh, tệp, âm thanh hoặc APK vào Vault, app thực hiện sao chép và mã hóa riêng biệt. Toàn bộ tệp gốc trong máy (Album / Thư mục Tải về) luôn được bảo toàn 100%, không bị xóa hay biến mất.
        </div>
      </div>

      <div className="rounded-2xl bg-white dark:bg-[#172021] border border-zinc-200/80 dark:border-zinc-800/80 p-4 shadow-xs">
        <div className="flex items-center justify-between">
          <div className="flex items-center gap-2">
            <Moon className="w-4 h-4 text-[#315e63] dark:text-[#78aeb3]" />
            <div>
              <div className="text-xs font-semibold text-zinc-900 dark:text-zinc-100">
                Dark Mode
              </div>
              <div className="text-[11px] text-zinc-400">
                Switch between high-contrast dark and light theme.
              </div>
            </div>
          </div>
          <input
            type="checkbox"
            checked={settings.darkMode}
            onChange={(e) => update({ darkMode: e.target.checked })}
            className="w-4 h-4 accent-[#315e63]"
          />
        </div>
      </div>

      <div className="rounded-2xl bg-white dark:bg-[#172021] border border-zinc-200/80 dark:border-zinc-800/80 p-4 shadow-xs space-y-2">
        <div className="flex items-center gap-2">
          <AppWindow className="w-4 h-4 text-[#315e63] dark:text-[#78aeb3]" />
          <h3 className="text-sm font-semibold text-zinc-900 dark:text-zinc-100">
            Launcher Disguise
          </h3>
        </div>
        <p className="text-xs text-zinc-500 dark:text-zinc-400 leading-relaxed">
          The application exposes benign cover tools while keeping the encrypted vault isolated.
          Active cover preference is set to{' '}
          <strong className="text-zinc-800 dark:text-zinc-200 capitalize">
            {settings.cover}
          </strong>
          .
        </p>
      </div>
    </div>
  );
};
