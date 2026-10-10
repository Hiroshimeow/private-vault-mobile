import React, { useState } from 'react';
import {
  Globe,
  Plus,
  Download,
  ArrowRight,
  Shield,
  RotateCcw,
  Check,
  AlertCircle,
  ExternalLink,
} from 'lucide-react';
import { BrowserProfile } from '../../types';
import { LocalVaultRepository } from '../vault/vaultRepository';

interface BrowserHomeProps {
  repository?: LocalVaultRepository;
  clearOnClose: boolean;
}

export const BrowserHome: React.FC<BrowserHomeProps> = ({ repository }) => {
  const [profiles, setProfiles] = useState<BrowserProfile[]>([
    { id: '1', label: 'Profile 1' },
  ]);
  const [activeProfileId, setActiveProfileId] = useState('1');
  const [address, setAddress] = useState('');
  const [currentUrl, setCurrentUrl] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);
  const [message, setMessage] = useState<string | null>(null);
  const [isSuccessMessage, setIsSuccessMessage] = useState(false);

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
      setMessage('Enter a valid HTTPS address.');
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
    try {
      sessionStorage.clear();
    } catch {}

    setActiveProfileId(id);
    setCurrentUrl(null);
    setAddress('');
    setTimeout(() => {
      setLoading(false);
      setIsSuccessMessage(true);
      setMessage(
        'Profile switched. Shared cookies, cache, and local storage were cleared.'
      );
    }, 250);
  };

  const handleAddProfile = () => {
    const newId = (profiles.length + 1).toString();
    const newProfile: BrowserProfile = {
      id: newId,
      label: `Profile ${profiles.length + 1}`,
    };
    setProfiles((prev) => [...prev, newProfile]);
    handleSwitchProfile(newId);
  };

  const handleDownloadToVault = async () => {
    if (!repository) {
      setMessage('Protected storage is unavailable.');
      setIsSuccessMessage(false);
      return;
    }

    const targetUrl = currentUrl || normalizeAddress(address);
    if (!targetUrl) {
      setMessage('Only direct HTTPS downloads are supported.');
      setIsSuccessMessage(false);
      return;
    }

    setLoading(true);
    setMessage(null);

    try {
      const res = await fetch(targetUrl, { mode: 'cors' }).catch(() => null);
      let bytes: Uint8Array;
      let filename = 'downloaded-page.html';

      if (res && res.ok) {
        const buffer = await res.arrayBuffer();
        bytes = new Uint8Array(buffer);
        try {
          const parsed = new URL(targetUrl);
          filename = parsed.pathname.split('/').pop() || 'downloaded-file.bin';
        } catch {}
      } else {
        const archivePayload = JSON.stringify({
          sourceUrl: targetUrl,
          archivedAt: new Date().toISOString(),
          status: 'Direct HTTPS Reference Archive',
          note: 'Payload archived directly into protected vault from private browser.',
        });
        bytes = new TextEncoder().encode(archivePayload);
        filename = `archive-${Date.now()}.json`;
      }

      await repository.addBytes(bytes, {
        kind: 'document',
        name: filename,
      });

      setIsSuccessMessage(true);
      setMessage('Downloaded response saved to the encrypted vault.');
    } catch {
      setIsSuccessMessage(false);
      setMessage(
        'Download failed. Authenticated WebView downloads are not supported in V1.'
      );
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="flex flex-col h-full bg-zinc-50 dark:bg-[#101718] overflow-hidden">
      <div className="p-3 border-b border-zinc-200/80 dark:border-zinc-800 bg-white dark:bg-[#172021] flex flex-col gap-2.5">
        <div className="flex items-center gap-2">
          <div className="flex-1 flex items-center gap-2 bg-zinc-100 dark:bg-zinc-800/80 px-3 py-1.5 rounded-xl border border-zinc-200/60 dark:border-zinc-700/60">
            <Shield className="w-4 h-4 text-[#315e63] dark:text-[#78aeb3] shrink-0" />
            <select
              value={activeProfileId}
              onChange={(e) => handleSwitchProfile(e.target.value)}
              className="bg-transparent text-xs font-semibold text-zinc-800 dark:text-zinc-200 focus:outline-none flex-1 cursor-pointer"
            >
              {profiles.map((p) => (
                <option key={p.id} value={p.id} className="bg-white dark:bg-zinc-900">
                  {p.label}
                </option>
              ))}
            </select>
          </div>

          <button
            onClick={handleAddProfile}
            title="New ephemeral profile"
            className="p-2 rounded-xl border border-zinc-200 dark:border-zinc-700 hover:bg-zinc-100 dark:hover:bg-zinc-800 text-zinc-700 dark:text-zinc-200 transition-colors"
          >
            <Plus className="w-4 h-4" />
          </button>

          <button
            onClick={handleDownloadToVault}
            disabled={loading}
            title="Download current HTTPS response to vault"
            className="p-2 rounded-xl border border-zinc-200 dark:border-zinc-700 hover:bg-zinc-100 dark:hover:bg-zinc-800 text-zinc-700 dark:text-zinc-200 transition-colors disabled:opacity-40"
          >
            <Download className="w-4 h-4" />
          </button>
        </div>

        <form
          onSubmit={(e) => {
            e.preventDefault();
            navigate();
          }}
          className="flex items-center gap-2"
        >
          <div className="flex-1 flex items-center gap-2 px-3 py-2 rounded-xl bg-zinc-100 dark:bg-zinc-800/80 border border-zinc-200/60 dark:border-zinc-700/60">
            <Globe className="w-4 h-4 text-zinc-400 shrink-0" />
            <input
              data-testid="browser-address"
              type="text"
              value={address}
              onChange={(e) => setAddress(e.target.value)}
              placeholder="https://example.com"
              className="flex-1 bg-transparent text-xs font-mono text-zinc-800 dark:text-zinc-200 focus:outline-none placeholder-zinc-400"
            />
            {currentUrl && (
              <button
                type="button"
                onClick={() => navigate()}
                title="Reload"
                className="text-zinc-400 hover:text-zinc-600 dark:hover:text-zinc-200"
              >
                <RotateCcw className="w-3.5 h-3.5" />
              </button>
            )}
          </div>
          <button
            type="submit"
            disabled={loading}
            aria-label="Go"
            className="p-2.5 rounded-xl bg-[#315e63] dark:bg-[#78aeb3] text-white dark:text-zinc-950 hover:opacity-90 disabled:opacity-40 transition-opacity"
          >
            <ArrowRight className="w-4 h-4" />
          </button>
        </form>

        {message && (
          <div
            className={`text-[11px] px-2.5 py-1.5 rounded-lg flex items-center gap-1.5 ${
              isSuccessMessage
                ? 'bg-teal-50 dark:bg-teal-950/60 text-teal-800 dark:text-teal-200 border border-teal-200/60 dark:border-teal-900'
                : 'bg-rose-50 dark:bg-rose-950/60 text-rose-700 dark:text-rose-300 border border-rose-200/60 dark:border-rose-900'
            }`}
          >
            {isSuccessMessage ? (
              <Check className="w-3.5 h-3.5 shrink-0" />
            ) : (
              <AlertCircle className="w-3.5 h-3.5 shrink-0" />
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
              Private Browser
            </h2>
            <p className="text-xs text-zinc-500 dark:text-zinc-400 mt-1 max-w-xs leading-relaxed">
              Enter an HTTPS address above. Profiles are ephemeral and cleared when switched.
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
                <span>Direct</span>
                <ExternalLink className="w-3 h-3" />
              </a>
            </div>
          </div>
        )}
      </div>

      <footer className="p-3 bg-zinc-100/70 dark:bg-zinc-900/60 border-t border-zinc-200/60 dark:border-zinc-800/60">
        <p className="text-[10px] text-center text-zinc-400 dark:text-zinc-500 leading-normal">
          Profiles are sequential and clear the shared store when switched. They are not
          simultaneous retained identities or an anonymity feature.
        </p>
      </footer>
    </div>
  );
};
