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

  const startStream = async (mode: 'user' | 'environment') => {
    if (streamRef.current) {
      streamRef.current.getTracks().forEach((t) => t.stop());
    }
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
    return () => {
      if (streamRef.current) {
        streamRef.current.getTracks().forEach((t) => t.stop());
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

    canvas.toBlob(async (blob) => {
      setIsCapturing(false);
      if (!blob) return;
      const buffer = await blob.arrayBuffer();
      const bytes = new Uint8Array(buffer);
      const name = `Camera_${Date.now()}.png`;

      await repository.addBytes(bytes, {
        kind: 'image',
        name,
        album: 'Máy ảnh',
        isFavorite: false,
        width: canvas.width,
        height: canvas.height,
      });

      const url = URL.createObjectURL(blob);
      setLastPhotoUrl(url);
      showToast('Đã lưu và mã hóa ảnh trực tiếp vào Thư mục Bảo mật');
    }, 'image/png');
  };

  const handleFlip = () => {
    setFacingMode((prev) => (prev === 'environment' ? 'user' : 'environment'));
  };

  return (
    <div className="flex flex-col h-full bg-black text-white select-none overflow-hidden relative font-sans">
      {/* Camera Top Bar */}
      <div className="p-4 flex items-center justify-between z-20 bg-gradient-to-b from-black/80 to-transparent">
        <button
          onClick={onBack}
          className="p-2 rounded-full bg-black/40 hover:bg-black/70 backdrop-blur-xs transition-colors"
        >
          <ChevronLeft className="w-5 h-5" />
        </button>

        <div className="text-center">
          <span className="text-xs font-bold uppercase tracking-wider text-teal-400">
            Máy ảnh bảo mật
          </span>
          <p className="text-[10px] text-zinc-400 font-mono">Lưu trữ không để lại dấu vết</p>
        </div>

        <button
          onClick={() => setFlashEnabled(!flashEnabled)}
          className={`p-2 rounded-full transition-colors ${
            flashEnabled ? 'bg-amber-500 text-black' : 'bg-black/40 text-white'
          }`}
        >
          {flashEnabled ? <Zap className="w-4 h-4" /> : <ZapOff className="w-4 h-4" />}
        </button>
      </div>

      {/* Viewfinder */}
      <div className="flex-1 relative overflow-hidden flex items-center justify-center">
        <video ref={videoRef} playsInline autoPlay className="w-full h-full object-cover" />

        {isCapturing && (
          <div className="absolute inset-0 bg-white opacity-80 animate-out fade-out duration-300 pointer-events-none" />
        )}
      </div>

      {/* Bottom Shutter Controls */}
      <div className="p-6 bg-gradient-to-t from-black via-black/90 to-transparent flex items-center justify-around z-20">
        {/* Gallery shortcut thumbnail */}
        <button
          onClick={onOpenGallery || onBack}
          className="w-12 h-12 rounded-xl bg-zinc-900 border border-zinc-700 overflow-hidden flex items-center justify-center shadow-md active:scale-95 transition-all"
          title="Xem Bộ sưu tập"
        >
          {lastPhotoUrl ? (
            <img src={lastPhotoUrl} alt="Thumbnail" className="w-full h-full object-cover" />
          ) : (
            <ImageIcon className="w-5 h-5 text-teal-400" />
          )}
        </button>

        {/* Shutter Button */}
        <button
          onClick={handleCapture}
          disabled={isCapturing}
          className="w-18 h-18 rounded-full border-4 border-white flex items-center justify-center hover:bg-white/20 active:scale-90 transition-all"
        >
          <div className="w-14 h-14 rounded-full bg-white shadow-xl" />
        </button>

        {/* Flip camera */}
        <button
          onClick={handleFlip}
          className="w-12 h-12 rounded-full bg-zinc-800/80 hover:bg-zinc-700 flex items-center justify-center text-white active:scale-95 transition-all"
          title="Đổi camera trước/sau"
        >
          <RotateCw className="w-5 h-5" />
        </button>
      </div>

      {toast && (
        <div className="absolute bottom-24 left-1/2 -translate-x-1/2 z-30 px-3.5 py-1.5 rounded-xl bg-teal-500 text-zinc-950 font-bold text-xs flex items-center gap-1.5 shadow-2xl animate-in fade-in">
          <CheckCircle2 className="w-4 h-4 shrink-0" />
          <span>{toast}</span>
        </div>
      )}
    </div>
  );
};
