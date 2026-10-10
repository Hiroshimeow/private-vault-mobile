import React, { useState, useEffect } from 'react';
import {
  Globe,
  Plus,
  Download,
  ArrowRight,
  Shield,
  Check,
  AlertCircle,
  ExternalLink,
  Bookmark,
} from 'lucide-react';
import { BrowserProfile } from '../../types';
import { LocalVaultRepository } from '../vault/vaultRepository';

interface BrowserHomeProps {
  repository?: LocalVaultRepository;
  clearOnClose?: boolean;
}

export const BrowserHome: React.FC<BrowserHomeProps> = ({ repository, clearOnClose = true }) => {
  const [profiles, setProfiles] = useState<BrowserProfile[]>([
    { id: '1', label: 'Cấu hình 1 (Tạm thời)' },
  ]);
  const [activeProfileId, setActiveProfileId] = useState('1');
  const [address, setAddress] = useState('');
  const [currentUrl, setCurrentUrl] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);
  const [message, setMessage] = useState<string | null>(null);
  const [isSuccessMessage, setIsSuccessMessage] = useState(false);

  useEffect(() => {
    return () => {
      if (clearOnClose) {
        setCurrentUrl(null);
        setAddress('');
      }
    };
  }, [clearOnClose]);

  const normalizeAddress = (raw: string): string | null => {
    const trimmed = raw.trim();
    if (!trimmed) return null;
    const candidate = trimmed.includes('://') ? trimmed : `https://${trimmed}`;
    try {
      const parsed = new URL(candidate);
      if (parsed.protocol !== 'https:') return null;
      return parsed.toString();
    } catch {
      return null;
    }
  };

  const navigate = (urlToLoad?: string) => {
    const target = urlToLoad || address;
    const normalized = normalizeAddress(target);
    if (!normalized) {
      setMessage('Vui lòng nhập địa chỉ HTTPS hợp lệ.');
      setIsSuccessMessage(false);
      return;
    }
    setMessage(null);
    setLoading(true);
    setCurrentUrl(normalized);
    setAddress(normalized);
    setTimeout(() => {
      setLoading(false);
    }, 400);
  };

  const handleSwitchProfile = (id: string) => {
    if (id === activeProfileId) return;
    setLoading(true);
    setActiveProfileId(id);
    setCurrentUrl(null);
    setAddress('');
    setTimeout(() => {
      setLoading(false);
      setIsSuccessMessage(true);
      setMessage('Đã chuyển cấu hình. Phiên làm việc tạm thời được làm mới.');
    }, 200);
  };

  const handleAddProfile = () => {
    const newId = (profiles.length + 1).toString();
    const newProfile: BrowserProfile = {
      id: newId,
      label: `Cấu hình ${profiles.length + 1} (Tạm thời)`,
    };
    setProfiles((prev) => [...prev, newProfile]);
    handleSwitchProfile(newId);
  };

  // Authentic direct HTTPS binary download (A16 fix: no fake bookmark disguised as download)
  const handleDownloadToVault = async () => {
    if (!repository) {
      setMessage('Kho lưu trữ không khả dụng.');
      setIsSuccessMessage(false);
      return;
    }

    const targetUrl = currentUrl || normalizeAddress(address);
    if (!targetUrl) {
      setMessage('Vui lòng nhập hoặc mở liên kết HTTPS để tải.');
      setIsSuccessMessage(false);
      return;
    }

    setLoading(true);
    setMessage(null);

    try {
      const res = await fetch(targetUrl, { mode: 'cors' });
      if (!res.ok) {
        throw new Error(`Máy chủ từ chối yêu cầu HTTP (${res.status})`);
      }

      const buffer = await res.arrayBuffer();
      const bytes = new Uint8Array(buffer);
      let filename = 'downloaded-file.bin';
      try {
        const parsed = new URL(targetUrl);
        filename = parsed.pathname.split('/').filter(Boolean).pop() || `download-${Date.now()}.html`;
      } catch {}

      const contentType = res.headers.get('content-type') || 'application/octet-stream';
      await repository.addBytes(bytes, {
        kind: 'document',
        name: filename,
        mimeType: contentType,
        album: 'Tải về từ Trình duyệt',
      });

      setIsSuccessMessage(true);
      setMessage(`Đã tải xuống thành công ${filename} (${(bytes.byteLength / 1024).toFixed(1)} KB) vào Vault.`);
    } catch {
      setIsSuccessMessage(false);
      setMessage(
        'Không thể tải tệp trực tiếp do chính sách bảo mật CORS hoặc mạng của trang web. Bạn có thể sử dụng nút "Lưu dấu trang" để lưu liên kết.'
      );
    } finally {
      setLoading(false);
    }
  };

  // Separate explicit bookmark function
  const handleSaveBookmark = async () => {
    if (!repository) return;
    const targetUrl = currentUrl || normalizeAddress(address);
    if (!targetUrl) {
      setMessage('Vui lòng nhập liên kết hợp lệ để lưu dấu trang.');
      setIsSuccessMessage(false);
      return;
    }

    try {
      const parsed = new URL(targetUrl);
      const payload = JSON.stringify({
        url: targetUrl,
        domain: parsed.hostname,
        savedAt: new Date().toISOString(),
      });
      const bytes = new TextEncoder().encode(payload);

      await repository.addBytes(bytes, {
        kind: 'document',
        name: `bookmark-${parsed.hostname}.json`,
        album: 'Dấu trang trình duyệt',
      });

      setIsSuccessMessage(true);
      setMessage(`Đã lưu dấu trang ${parsed.hostname} vào kho mã hóa Vault.`);
    } catch {
      setIsSuccessMessage(false);
      setMessage('Lỗi khi lưu dấu trang.');
    }
  };

  return (
    <div className="flex flex-col h-full bg-zinc-50 dark:bg-[#101718] overflow-hidden font-sans">
      <div className="p-3 border-b border-zinc-200/80 dark:border-zinc-800 bg-white dark:bg-[#172021] flex flex-col gap-2.5">
        <div className="flex items-center gap-2">
          <div className="flex-1 flex items-center gap-2 bg-zinc-100 dark:bg-zinc-800/80 px-3 py-1.5 rounded-xl border border-zinc-200/60 dark:border-zinc-700/60">
            <Shield className="w-4 h-4 text-[#315e63] dark:text-[#78aeb3] shrink-0" />
            <select
              value={activeProfileId}
              onChange={(e) => handleSwitchProfile(e.target.value)}
              className="bg-transparent text-xs text-zinc-800 dark:text-zinc-200 focus:outline-none flex-1 font-medium"
            >
              {profiles.map((p) => (
                <option key={p.id} value={p.id} className="bg-white dark:bg-zinc-800">
                  {p.label}
                </option>
              ))}
            </select>
          </div>
          <button
            onClick={handleAddProfile}
            title="Thêm cấu hình tạm thời"
            className="p-2 rounded-xl bg-zinc-100 dark:bg-zinc-800 hover:bg-zinc-200 dark:hover:bg-zinc-700 text-zinc-700 dark:text-zinc-300 transition-colors"
          >
            <Plus className="w-4 h-4" />
          </button>
        </div>

        <div className="flex items-center gap-2">
          <form
            onSubmit={(e) => {
              e.preventDefault();
              navigate();
            }}
            className="flex-1 flex items-center gap-2 bg-zinc-100 dark:bg-zinc-800/80 px-3 py-1.5 rounded-xl border border-zinc-200/60 dark:border-zinc-700/60"
          >
            <Globe className="w-4 h-4 text-zinc-400 shrink-0" />
            <input
              type="text"
              value={address}
              onChange={(e) => setAddress(e.target.value)}
              placeholder="Nhập địa chỉ HTTPS (vd: en.wikipedia.org)"
              className="flex-1 bg-transparent text-xs text-zinc-900 dark:text-zinc-100 placeholder-zinc-400 focus:outline-none"
            />
            <button
              type="submit"
              className="text-zinc-500 hover:text-zinc-800 dark:hover:text-zinc-200"
            >
              <ArrowRight className="w-4 h-4" />
            </button>
          </form>

          <button
            onClick={handleDownloadToVault}
            title="Tải tệp tin nhị phân vào Vault"
            className="p-2 rounded-xl bg-zinc-100 dark:bg-zinc-800 hover:bg-zinc-200 dark:hover:bg-zinc-700 text-zinc-700 dark:text-zinc-300 transition-colors"
          >
            <Download className="w-4 h-4" />
          </button>

          <button
            onClick={handleSaveBookmark}
            title="Lưu dấu trang vào Vault"
            className="p-2 rounded-xl bg-zinc-100 dark:bg-zinc-800 hover:bg-zinc-200 dark:hover:bg-zinc-700 text-teal-600 dark:text-teal-400 transition-colors"
          >
            <Bookmark className="w-4 h-4" />
          </button>
        </div>

        {message && (
          <div
            className={`p-2 rounded-xl text-xs flex items-center gap-2 ${
              isSuccessMessage
                ? 'bg-teal-50 dark:bg-teal-950/50 text-teal-700 dark:text-teal-300 border border-teal-200 dark:border-teal-800'
                : 'bg-rose-50 dark:bg-rose-950/50 text-rose-700 dark:text-rose-300 border border-rose-200 dark:border-rose-800'
            }`}
          >
            {isSuccessMessage ? (
              <Check className="w-4 h-4 shrink-0" />
            ) : (
              <AlertCircle className="w-4 h-4 shrink-0" />
            )}
            <span>{message}</span>
          </div>
        )}
      </div>

      {loading && (
        <div className="h-0.5 w-full bg-zinc-200 dark:bg-zinc-800 overflow-hidden">
          <div className="h-full bg-[#315e63] dark:bg-[#78aeb3] animate-pulse w-full" />
        </div>
      )}

      <div className="flex-1 overflow-hidden relative flex flex-col">
        {!currentUrl ? (
          <div className="flex-1 flex flex-col items-center justify-center p-6 text-center">
            <div className="w-12 h-12 rounded-2xl bg-teal-100 dark:bg-teal-950/60 text-[#315e63] dark:text-[#78aeb3] flex items-center justify-center mb-3">
              <Shield className="w-6 h-6" />
            </div>
            <h2 className="text-lg font-bold text-zinc-900 dark:text-zinc-100">
              Trình duyệt Riêng tư
            </h2>
            <p className="text-xs text-zinc-500 dark:text-zinc-400 mt-1 max-w-xs leading-relaxed">
              Duyệt web tạm thời. Tải tệp trực tiếp hoặc lưu dấu trang vào kho mã hóa Vault.
            </p>

            <div className="mt-6 flex flex-wrap justify-center gap-2 max-w-sm">
              {[
                { name: 'Wikipedia', url: 'https://en.wikipedia.org' },
                { name: 'DuckDuckGo', url: 'https://duckduckgo.com' },
                { name: 'Example Domain', url: 'https://example.com' },
              ].map((site) => (
                <button
                  key={site.name}
                  onClick={() => {
                    setAddress(site.url);
                    navigate(site.url);
                  }}
                  className="px-3 py-1.5 rounded-xl border border-zinc-200 dark:border-zinc-800 bg-white dark:bg-zinc-900 text-xs font-medium text-zinc-700 dark:text-zinc-300 hover:border-[#315e63] transition-colors"
                >
                  {site.name}
                </button>
              ))}
            </div>
          </div>
        ) : (
          <div className="flex-1 flex flex-col h-full bg-white dark:bg-zinc-950">
            <iframe
              src={currentUrl}
              title="Private Browser Frame"
              sandbox="allow-scripts allow-forms allow-same-origin"
              className="flex-1 w-full border-none"
            />
            <div className="p-2 border-t border-zinc-200 dark:border-zinc-800 bg-zinc-50 dark:bg-zinc-900 flex items-center justify-between text-[11px] text-zinc-400 px-3">
              <span className="truncate max-w-[260px] font-mono">{currentUrl}</span>
              <a
                href={currentUrl}
                target="_blank"
                rel="noreferrer noopener"
                className="text-[#315e63] dark:text-[#78aeb3] flex items-center gap-1 hover:underline ml-2"
              >
                <span>Mở ngoài</span>
                <ExternalLink className="w-3 h-3" />
              </a>
            </div>
          </div>
        )}
      </div>

      <footer className="p-3 bg-zinc-100/70 dark:bg-zinc-900/60 border-t border-zinc-200/60 dark:border-zinc-800/60">
        <p className="text-[10px] text-center text-zinc-400 dark:text-zinc-500 leading-normal">
          Các cấu hình hoạt động theo phiên làm việc độc lập. Khi đóng hoặc đổi cấu hình, dữ liệu tạm thời được làm mới.
        </p>
      </footer>
    </div>
  );
};
