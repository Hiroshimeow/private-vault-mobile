import React, { useState, useRef, useEffect } from 'react';
import {
  Mic,
  Square,
  Play,
  Pause,
  Trash2,
  Download,
  ChevronLeft,
  CheckCircle2,
} from 'lucide-react';
import { LocalVaultRepository } from '../vault/vaultRepository';
import { VaultItem } from '../../types';
import { VaultSessionManager } from '../vault/vaultSession';

interface SecureAudioRecorderProps {
  onBack: () => void;
  repository: LocalVaultRepository;
  confirmExport?: boolean;
}

export const SecureAudioRecorder: React.FC<SecureAudioRecorderProps> = ({
  onBack,
  repository,
  confirmExport = true,
}) => {
  const [recordings, setRecordings] = useState<VaultItem[]>([]);
  const [isRecording, setIsRecording] = useState(false);
  const [recordingSeconds, setRecordingSeconds] = useState(0);
  const [activePlayId, setActivePlayId] = useState<string | null>(null);
  const [playAudioUrl, setPlayAudioUrl] = useState<string | null>(null);
  const [toast, setToast] = useState<string | null>(null);

  const mediaRecorderRef = useRef<MediaRecorder | null>(null);
  const activeStreamRef = useRef<MediaStream | null>(null);
  const audioChunksRef = useRef<Blob[]>([]);
  const timerIntervalRef = useRef<ReturnType<typeof setInterval> | null>(null);
  const audioPlayerRef = useRef<HTMLAudioElement | null>(null);
  const recordStartTimeRef = useRef<number>(0);

  const showToast = (msg: string) => {
    setToast(msg);
    setTimeout(() => setToast(null), 3000);
  };

  const loadRecordings = async () => {
    try {
      const all = await repository.list();
      setRecordings(all.filter((i) => i.kind === 'audio'));
    } catch (err) {
      console.error(err);
    }
  };

  const cleanupAudio = () => {
    if (timerIntervalRef.current) {
      clearInterval(timerIntervalRef.current);
      timerIntervalRef.current = null;
    }
    if (activeStreamRef.current) {
      activeStreamRef.current.getTracks().forEach((t) => t.stop());
      activeStreamRef.current = null;
    }
    if (mediaRecorderRef.current && mediaRecorderRef.current.state !== 'inactive') {
      try {
        mediaRecorderRef.current.stop();
      } catch {}
    }
    if (playAudioUrl) {
      URL.revokeObjectURL(playAudioUrl);
      setPlayAudioUrl(null);
    }
    setIsRecording(false);
    setActivePlayId(null);
  };

  useEffect(() => {
    loadRecordings();
    const unsub = VaultSessionManager.getInstance().subscribe(() => {
      cleanupAudio();
    });
    return () => {
      cleanupAudio();
      unsub();
    };
  }, [repository]);

  const startRecording = async () => {
    audioChunksRef.current = [];
    cleanupAudio();

    try {
      const stream = await navigator.mediaDevices.getUserMedia({ audio: true });
      activeStreamRef.current = stream;

      let chosenMime = 'audio/webm';
      if (typeof MediaRecorder.isTypeSupported === 'function') {
        if (MediaRecorder.isTypeSupported('audio/webm;codecs=opus')) {
          chosenMime = 'audio/webm;codecs=opus';
        } else if (MediaRecorder.isTypeSupported('audio/mp4')) {
          chosenMime = 'audio/mp4';
        }
      }

      const mediaRecorder = new MediaRecorder(stream, { mimeType: chosenMime });
      mediaRecorderRef.current = mediaRecorder;
      recordStartTimeRef.current = Date.now();

      mediaRecorder.ondataavailable = (e) => {
        if (e.data.size > 0) {
          audioChunksRef.current.push(e.data);
        }
      };

      mediaRecorder.onstop = async () => {
        if (activeStreamRef.current) {
          activeStreamRef.current.getTracks().forEach((track) => track.stop());
          activeStreamRef.current = null;
        }

        if (audioChunksRef.current.length === 0) return;

        const audioBlob = new Blob(audioChunksRef.current, { type: chosenMime });
        const buffer = await audioBlob.arrayBuffer();
        const bytes = new Uint8Array(buffer);

        // Calculate duration accurately from elapsed time
        const elapsedSec = Math.max(1, Math.round((Date.now() - recordStartTimeRef.current) / 1000));
        const mins = Math.floor(elapsedSec / 60);
        const secs = elapsedSec % 60;
        const durStr = `${mins}:${secs < 10 ? '0' : ''}${secs}`;

        const ext = chosenMime.includes('mp4') ? 'm4a' : 'webm';
        const name = `Voice_${new Date().toLocaleTimeString([], { hour: '2-digit', minute: '2-digit', second: '2-digit' })}.${ext}`;
        
        await repository.addBytes(bytes, {
          kind: 'audio',
          name,
          mimeType: chosenMime,
          album: 'Ghi âm bảo mật',
          duration: durStr,
        });

        setRecordingSeconds(0);
        showToast('Đã mã hóa và lưu bản ghi âm vào Vault');
        await loadRecordings();
      };

      mediaRecorder.start(200);
      setIsRecording(true);
      setRecordingSeconds(0);

      timerIntervalRef.current = setInterval(() => {
        setRecordingSeconds((prev) => prev + 1);
      }, 1000);
    } catch {
      showToast('Không thể truy cập microphone của thiết bị');
    }
  };

  const stopRecording = () => {
    if (mediaRecorderRef.current && isRecording) {
      mediaRecorderRef.current.stop();
      setIsRecording(false);
      if (timerIntervalRef.current) {
        clearInterval(timerIntervalRef.current);
        timerIntervalRef.current = null;
      }
    }
  };

  const handlePlayAudio = async (item: VaultItem) => {
    if (activePlayId === item.id) {
      if (audioPlayerRef.current) {
        audioPlayerRef.current.pause();
        setActivePlayId(null);
      }
      return;
    }

    try {
      const data = await repository.readBytes(item.id);
      if (playAudioUrl) URL.revokeObjectURL(playAudioUrl);

      const blob = new Blob([data.bytes], { type: data.mimeType || 'audio/webm' });
      const url = URL.createObjectURL(blob);
      setPlayAudioUrl(url);
      setActivePlayId(item.id);

      if (audioPlayerRef.current) {
        audioPlayerRef.current.src = url;
        audioPlayerRef.current.play();
      }
    } catch {
      showToast('Không thể giải mã bản ghi âm');
    }
  };

  const handleDeleteAudio = async (id: string) => {
    if (!window.confirm('Xóa bản ghi âm này vĩnh viễn?')) return;
    await repository.delete(id);
    if (activePlayId === id) {
      if (audioPlayerRef.current) audioPlayerRef.current.pause();
      setActivePlayId(null);
      if (playAudioUrl) URL.revokeObjectURL(playAudioUrl);
    }
    await loadRecordings();
    showToast('Đã xóa bản ghi âm');
  };

  const handleExport = async (item: VaultItem) => {
    if (confirmExport) {
      const ok = window.confirm(
        `Bạn có chắc chắn muốn xuất bản ghi âm "${item.name}" ra bộ nhớ máy không? Tệp xuất ra sẽ không còn được mã hóa.`
      );
      if (!ok) return;
    }

    try {
      const data = await repository.readBytes(item.id);
      const mime = data.mimeType || 'audio/webm';
      const blob = new Blob([data.bytes], { type: mime });
      const url = URL.createObjectURL(blob);
      const a = document.createElement('a');
      a.href = url;
      a.download = data.name || `recording-${item.id.slice(0, 6)}.webm`;
      document.body.appendChild(a);
      a.click();
      document.body.removeChild(a);
      setTimeout(() => URL.revokeObjectURL(url), 1000);
      showToast('Đã xuất bản sao ghi âm về máy');
    } catch {
      showToast('Lỗi xuất tệp');
    }
  };

  const formatTimer = (sec: number) => {
    const m = Math.floor(sec / 60);
    const s = sec % 60;
    return `${m < 10 ? '0' : ''}${m}:${s < 10 ? '0' : ''}${s}`;
  };

  return (
    <div className="flex flex-col h-full bg-[#0d1416] text-zinc-100 select-none overflow-hidden font-sans">
      <audio
        ref={audioPlayerRef}
        onEnded={() => setActivePlayId(null)}
        className="hidden"
      />

      {/* Header */}
      <div className="bg-[#141e21] text-white px-3.5 py-3 flex items-center justify-between border-b border-zinc-800 shadow-md shrink-0">
        <div className="flex items-center gap-2.5">
          <button onClick={onBack} className="p-1 rounded-full hover:bg-white/10">
            <ChevronLeft className="w-5 h-5" />
          </button>
          <div>
            <h3 className="text-sm font-bold">Ghi âm Bảo mật</h3>
            <p className="text-[10px] text-teal-400">Mã hóa AES-256 tức thì</p>
          </div>
        </div>
      </div>

      {toast && (
        <div className="p-2.5 bg-teal-950/80 border-b border-teal-800 text-teal-300 text-xs text-center flex items-center justify-center gap-1.5 font-medium animate-in fade-in">
          <CheckCircle2 className="w-3.5 h-3.5" />
          <span>{toast}</span>
        </div>
      )}

      {/* Main Studio / Recording area */}
      <div className="p-6 flex flex-col items-center justify-center bg-[#10191b] border-b border-zinc-800 shrink-0">
        <div className="font-mono text-4xl font-light text-zinc-100 tracking-wider mb-6">
          {formatTimer(recordingSeconds)}
        </div>

        {isRecording ? (
          <button
            onClick={stopRecording}
            className="w-20 h-20 rounded-full bg-rose-500 hover:bg-rose-600 text-white flex items-center justify-center shadow-lg shadow-rose-900/40 active:scale-95 transition-all animate-pulse"
          >
            <Square className="w-8 h-8 fill-current" />
          </button>
        ) : (
          <button
            onClick={startRecording}
            className="w-20 h-20 rounded-full bg-teal-500 hover:bg-teal-400 text-zinc-950 flex items-center justify-center shadow-lg shadow-teal-900/40 active:scale-95 transition-all"
          >
            <Mic className="w-8 h-8" />
          </button>
        )}

        <span className="text-xs text-zinc-400 mt-4 font-medium">
          {isRecording ? 'Đang ghi âm bí mật... Bấm để lưu' : 'Bấm micro để bắt đầu ghi âm'}
        </span>
      </div>

      {/* Recordings list */}
      <div className="flex-1 overflow-y-auto p-4 space-y-2.5">
        <div className="text-xs uppercase font-semibold tracking-wider text-zinc-400 px-1 mb-2">
          Danh sách bản ghi ({recordings.length})
        </div>

        {recordings.length === 0 ? (
          <div className="flex flex-col items-center justify-center py-16 text-center text-zinc-500 space-y-2">
            <Mic className="w-8 h-8 text-zinc-600" />
            <p className="text-xs">Chưa có bản ghi âm nào trong Vault</p>
          </div>
        ) : (
          recordings.map((item) => (
            <div
              key={item.id}
              className={`p-3.5 rounded-2xl border transition-all flex items-center justify-between shadow-xs ${
                activePlayId === item.id
                  ? 'bg-[#182629] border-teal-500/50'
                  : 'bg-[#131d1f] border-zinc-800/80 hover:border-zinc-700'
              }`}
            >
              <div className="flex items-center gap-3 min-w-0">
                <button
                  onClick={() => handlePlayAudio(item)}
                  className={`w-10 h-10 rounded-xl flex items-center justify-center transition-colors shrink-0 ${
                    activePlayId === item.id
                      ? 'bg-teal-400 text-zinc-950'
                      : 'bg-zinc-800 text-teal-400 hover:bg-zinc-700'
                  }`}
                >
                  {activePlayId === item.id ? (
                    <Pause className="w-5 h-5 fill-current" />
                  ) : (
                    <Play className="w-5 h-5 fill-current ml-0.5" />
                  )}
                </button>

                <div className="min-w-0">
                  <h4 className="text-xs font-bold text-zinc-100 truncate">
                    {item.name || 'Bản ghi âm'}
                  </h4>
                  <div className="flex items-center gap-2 text-[10px] text-zinc-400 mt-0.5 font-mono">
                    <span>{item.duration || '0:00'}</span>
                    <span>·</span>
                    <span>{new Date(item.createdAt).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}</span>
                  </div>
                </div>
              </div>

              <div className="flex items-center gap-1 shrink-0">
                <button
                  onClick={() => handleExport(item)}
                  className="p-2 text-zinc-400 hover:text-teal-400 rounded-lg hover:bg-zinc-800"
                  title="Xuất file âm thanh"
                >
                  <Download className="w-4 h-4" />
                </button>
                <button
                  onClick={() => handleDeleteAudio(item.id)}
                  className="p-2 text-zinc-400 hover:text-rose-400 rounded-lg hover:bg-zinc-800"
                  title="Xóa bản ghi"
                >
                  <Trash2 className="w-4 h-4" />
                </button>
              </div>
            </div>
          ))
        )}
      </div>
    </div>
  );
};
