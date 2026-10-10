import React, { useState, useEffect } from 'react';
import { VaultItem } from '../../types';
import { LocalVaultRepository } from '../vault/vaultRepository';
import { thumbnailCache } from './thumbnailCache';
import { Image as ImageIcon, Play } from 'lucide-react';

interface VaultThumbnailProps {
  item: VaultItem;
  repository: LocalVaultRepository;
  className?: string;
}

export const VaultThumbnail: React.FC<VaultThumbnailProps> = ({
  item,
  repository,
  className = '',
}) => {
  // Synchronously initialize from persistent in-memory cache
  const [thumbUrl, setThumbUrl] = useState<string | null>(() => thumbnailCache.get(item.id) || null);
  const [error, setError] = useState(false);

  useEffect(() => {
    // If already in cache, no need to decrypt again
    const cached = thumbnailCache.get(item.id);
    if (cached) {
      if (thumbUrl !== cached) setThumbUrl(cached);
      return;
    }

    let isMounted = true;

    repository
      .readBytes(item.id)
      .then((data) => {
        if (!isMounted) return;
        const ext = data.name.split('.').pop()?.toLowerCase();
        const mimeMap: Record<string, string> = {
          jpg: 'image/jpeg',
          jpeg: 'image/jpeg',
          png: 'image/png',
          webp: 'image/webp',
          svg: 'image/svg+xml',
          gif: 'image/gif',
          mp4: 'video/mp4',
          webm: 'video/webm',
          mov: 'video/quicktime',
        };
        const mime =
          data.mimeType ||
          (ext ? mimeMap[ext] : null) ||
          (data.kind === 'video' ? 'video/mp4' : 'image/jpeg');
        const blob = new Blob([data.bytes], { type: mime });
        const createdUrl = URL.createObjectURL(blob);
        thumbnailCache.set(item.id, createdUrl);
        setThumbUrl(createdUrl);
      })
      .catch(() => {
        if (isMounted) setError(true);
      });

    return () => {
      isMounted = false;
      // Do NOT revokeObjectURL here! Keep in persistent cache for instant tab switches
    };
  }, [item.id, repository, thumbUrl]);

  if (error || !thumbUrl) {
    return (
      <div
        className={`w-full h-full flex flex-col items-center justify-center bg-zinc-900 text-zinc-500 animate-pulse ${className}`}
      >
        <ImageIcon className="w-5 h-5 text-zinc-600 mb-1" />
        <span className="text-[9px] font-mono text-zinc-500 truncate max-w-[70px]">
          {item.name || 'Đang tải...'}
        </span>
      </div>
    );
  }

  if (item.kind === 'video') {
    return (
      <div className={`relative w-full h-full bg-black overflow-hidden group ${className}`}>
        <video
          src={thumbUrl}
          className="w-full h-full object-cover"
          preload="metadata"
          muted
        />
        <div className="absolute inset-0 bg-black/30 flex items-center justify-center group-hover:bg-black/20 transition-colors">
          <div className="w-8 h-8 rounded-full bg-black/60 backdrop-blur-xs flex items-center justify-center text-teal-400">
            <Play className="w-4 h-4 fill-current ml-0.5" />
          </div>
        </div>
        <div className="absolute bottom-1 right-1 px-1.5 py-0.5 rounded-md bg-black/80 backdrop-blur-xs text-[9px] font-mono text-zinc-200">
          {item.duration || '0:15'}
        </div>
      </div>
    );
  }

  return (
    <div className={`w-full h-full overflow-hidden bg-zinc-950 ${className}`}>
      <img
        src={thumbUrl}
        alt={item.name || 'Vault photo'}
        className="w-full h-full object-cover transition-transform duration-200 group-hover:scale-105"
        loading="lazy"
      />
    </div>
  );
};
