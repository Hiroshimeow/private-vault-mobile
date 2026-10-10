import React, { useState, useEffect, useRef } from 'react';
import {
  ChevronLeft,
  RotateCw,
  Zap,
  ZapOff,
  Image as ImageIcon,
  CheckCircle2,
} from 'lucide-react';
import { LocalVaultRepository } from '../../vault/vaultRepository';
import { VaultSessionManager } from '../../vault/vaultSession';

interface SecureCameraAppViewProps {
  onBack: () => void;
  repository: LocalVaultRepository;
  onOpenGallery?: () => void;
}

export const SecureCameraAppView: React.FC<SecureCameraAppViewProps> = ({
  onBack,
  repository,
  onOpenGallery,
}) => {
  const videoRef = useRef<HTMLVideoElement | null>(null);
  const streamRef = useRef<MediaStream | null>(null);
  const [facingMode, setFacingMode] = useState<'user' | 'environment'>('environment');
  const [flashEnabled, setFlashEnabled] = useState(false);
  const [lastPhotoUrl, setLastPhotoUrl] = useState<string | null>(null);
  const [isCapturing, setIsCapturing] = useState(false);
  const [toast, setToast] = useState<string | null>(null);

  const showToast = (msg: string) => {
    setToast(msg);
    setTimeout(() => setToast(null), 3000);
  };

  const stopStream = () => {
    if (streamRef.current) {
      streamRef.current.getTracks().forEach((t) => t.stop());
      streamRef.current = null;
    }
  };

  const startStream = async (mode: 'user' | 'environment') => {
    stopStream();
    try {
      const stream = await navigator.mediaDevices.getUserMedia({
        video: { facingMode: mode, width: { ideal: 1920 }, height: { ideal: 1080 } },
      });
      streamRef.current = stream;
      if (videoRef.current) {
        videoRef.current.srcObject = stream;
        videoRef.current.play();
      }
    } catch {
      try {
        const stream = await navigator.mediaDevices.getUserMedia({ video: true });
        streamRef.current = stream;
        if (videoRef.current) {
          videoRef.current.srcObject = stream;
          videoRef.current.play();
        }
      } catch (err) {
        console.error('Camera failed:', err);
        showToast('Không thể kết nối máy ảnh thiết bị');
      }
    }
  };

  useEffect(() => {
    startStream(facingMode);
    const unsub = VaultSessionManager.getInstance().subscribe(() => {
      stopStream();
      if (lastPhotoUrl) {
        URL.revokeObjectURL(lastPhotoUrl);
        setLastPhotoUrl(null);
      }
    });
    return () => {
      stopStream();
      unsub();
      if (lastPhotoUrl) {
        URL.revokeObjectURL(lastPhotoUrl);
      }
    };
  }, [facingMode]);

  const handleCapture = async () => {
    if (!videoRef.current) return;
    setIsCapturing(true);

    const canvas = document.createElement('canvas');
    canvas.width = videoRef.current.videoWidth || 1280;
    canvas.height = videoRef.current.videoHeight || 720;
    const ctx = canvas.getContext('2d');
    if (!ctx) {
      setIsCapturing(false);
      return;
    }

    ctx.drawImage(videoRef.current, 0, 0, canvas.width, canvas.height);

    canvas.toBlob(
      async (blob) => {
        if (!blob) {
          setIsCapturing(false);
          return;
        }

        try {
          const buffer = await blob.arrayBuffer();
          const bytes = new Uint8Array(buffer);
          const name = `IMG_${new Date().toISOString().replace(/[:.]/g, '-')}.jpg`;

          await repository.addBytes(bytes, {
            kind: 'image',
            name,
            mimeType: 'image/jpeg',
            album: 'Máy ảnh',
            width: canvas.width,
            height: canvas.height,
          });

          if (lastPhotoUrl) URL.revokeObjectURL(lastPhotoUrl);
          const newUrl = URL.createObjectURL(blob);
          setLastPhotoUrl(newUrl);

          showToast('Đã lưu & mã hóa vào Thư mục Bảo mật');
        } catch {
          showToast('Lỗi khi mã hóa ảnh chụp');
        } finally {
          setIsCapturing(false);
        }
      },
      'image/jpeg',
      0.95
    );
  };

  const toggleCamera = () => {
    setFacingMode((prev) => (prev === 'environment' ? 'user' : 'environment'));
  };

  return (
    <div className="flex flex-col h-full bg-black text-white select-none overflow-hidden font-sans relative">
      {/* Viewfinder Header */}
      <div className="absolute top-0 inset-x-0 z-20 flex items-center justify-between p-4 bg-gradient-to-b from-black/80 to-transparent">
        <button
          onClick={() => {
            stopStream();
            onBack();
          }}
          className="p-2 rounded-full bg-black/40 backdrop-blur-md hover:bg-black/60 transition-colors"
        >
          <ChevronLeft className="w-6 h-6" />
        </button>

        <div className="flex items-center gap-2">
          <button
            onClick={() => setFlashEnabled(!flashEnabled)}
            className="p-2 rounded-full bg-black/40 backdrop-blur-md hover:bg-black/60 transition-colors text-amber-300"
          >
            {flashEnabled ? <Zap className="w-5 h-5 fill-current" /> : <ZapOff className="w-5 h-5" />}
          </button>
        </div>
      </div>

      {toast && (
        <div className="absolute top-16 left-1/2 -translate-x-1/2 z-30 px-4 py-2 bg-teal-950/90 border border-teal-500/50 rounded-xl text-xs text-teal-300 shadow-xl flex items-center gap-2">
          <CheckCircle2 className="w-4 h-4" />
          <span>{toast}</span>
        </div>
      )}

      {/* Video Viewfinder */}
      <div className="flex-1 relative bg-black flex items-center justify-center overflow-hidden">
        <video
          ref={videoRef}
          playsInline
          autoPlay
          muted
          className="w-full h-full object-cover"
        />
        {isCapturing && (
          <div className="absolute inset-0 bg-white animate-in fade-in duration-100 opacity-80 pointer-events-none" />
        )}
      </div>

      {/* Bottom Shutter Controls */}
      <div className="h-28 bg-black/90 backdrop-blur-md flex items-center justify-around px-8 shrink-0 z-20">
        <button
          onClick={() => {
            stopStream();
            onOpenGallery?.();
          }}
          className="w-12 h-12 rounded-xl bg-zinc-800 border border-zinc-700 flex items-center justify-center overflow-hidden"
        >
          {lastPhotoUrl ? (
            <img src={lastPhotoUrl} alt="Thumbnail" className="w-full h-full object-cover" />
          ) : (
            <ImageIcon className="w-5 h-5 text-zinc-400" />
          )}
        </button>

        <button
          onClick={handleCapture}
          disabled={isCapturing}
          className="w-18 h-18 rounded-full border-4 border-white flex items-center justify-center p-1 active:scale-95 transition-transform"
        >
          <div className="w-full h-full rounded-full bg-white hover:bg-zinc-200 transition-colors" />
        </button>

        <button
          onClick={toggleCamera}
          className="w-12 h-12 rounded-full bg-zinc-800 border border-zinc-700 flex items-center justify-center text-zinc-300 hover:text-white"
        >
          <RotateCw className="w-5 h-5" />
        </button>
      </div>
    </div>
  );
};
