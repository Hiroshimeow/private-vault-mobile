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

interface SecureAudioRecorderProps {
  onBack: () => void;
  repository: LocalVaultRepository;
}

export const SecureAudioRecorder: React.FC<SecureAudioRecorderProps> = ({
  onBack,
  repository,
}) => {
  const [recordings, setRecordings] = useState<VaultItem[]>([]);
  const [isRecording, setIsRecording] = useState(false);
  const [recordingSeconds, setRecordingSeconds] = useState(0);
  const [activePlayId, setActivePlayId] = useState<string | null>(null);
  const [playAudioUrl, setPlayAudioUrl] = useState<string | null>(null);
  const [toast, setToast] = useState<string | null>(null);

  const mediaRecorderRef = useRef<MediaRecorder | null>(null);
  const audioChunksRef = useRef<Blob[]>([]);
  const timerIntervalRef = useRef<ReturnType<typeof setInterval> | null>(null);
  const audioPlayerRef = useRef<HTMLAudioElement | null>(null);

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

  useEffect(() => {
    loadRecordings();
    return () => {
      if (timerIntervalRef.current) clearInterval(timerIntervalRef.current);
      if (playAudioUrl) URL.revokeObjectURL(playAudioUrl);
    };
  }, [repository]);

  const startRecording = async () => {
    audioChunksRef.current = [];
    try {
      const stream = await navigator.mediaDevices.getUserMedia({ audio: true });
      const mediaRecorder = new MediaRecorder(stream);
      mediaRecorderRef.current = mediaRecorder;

      mediaRecorder.ondataavailable = (e) => {
        if (e.data.size > 0) {
          audioChunksRef.current.push(e.data);
        }
      };

      mediaRecorder.onstop = async () => {
        stream.getTracks().forEach((track) => track.stop());
        const audioBlob = new Blob(audioChunksRef.current, { type: 'audio/webm' });
        const buffer = await audioBlob.arrayBuffer();
        const bytes = new Uint8Array(buffer);

        const mins = Math.floor(recordingSeconds / 60);
        const secs = recordingSeconds % 60;
        const durStr = `${mins}:${secs < 10 ? '0' : ''}${secs}`;

        const name = `Voice_${new Date().toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}.webm`;
        await repository.addBytes(bytes, {
          kind: 'audio',
          name,
          album: 'Ghi âm bảo mật',
          duration: durStr,
        });

        setRecordingSeconds(0);
        showToast('Đã mã hóa và lưu file ghi âm vào Thư mục Bảo mật');
        await loadRecordings();
      };

      mediaRecorder.start(200);
      setIsRecording(true);
      setRecordingSeconds(0);

      timerIntervalRef.current = setInterval(() => {
        setRecordingSeconds((prev) => prev + 1);
      }, 1000);
    } catch {
      showToast('Không có quyền truy cập micro thiết bị');
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
        if (audioPlayerRef.current.paused) {
          audioPlayerRef.current.play();
        } else {
          audioPlayerRef.current.pause();
        }
      }
      return;
    }

    try {
      const data = await repository.readBytes(item.id);
      const blob = new Blob([data.bytes], { type: 'audio/webm' });
      if (playAudioUrl) URL.revokeObjectURL(playAudioUrl);
      const url = URL.createObjectURL(blob);
      setPlayAudioUrl(url);
      setActivePlayId(item.id);

      if (audioPlayerRef.current) {
        audioPlayerRef.current.src = url;
        audioPlayerRef.current.play();
      }
    } catch {
      showToast('Không thể giải mã file ghi âm');
    }
  };

  const handleDelete = async (item: VaultItem) => {
    if (!window.confirm(`Xóa bản ghi âm "${item.name}"?`)) return;
    await repository.delete(item.id);
    if (activePlayId === item.id) {
      setActivePlayId(null);
      if (playAudioUrl) URL.revokeObjectURL(playAudioUrl);
    }
    await loadRecordings();
    showToast('Đã xóa bản ghi âm');
  };

  const handleExport = async (item: VaultItem) => {
    try {
      const data = await repository.readBytes(item.id);
      const blob = new Blob([data.bytes], { type: 'audio/webm' });
      const url = URL.createObjectURL(blob);
      const a = document.createElement('a');
      a.href = url;
      a.download = data.name || `recording-${item.id.slice(0, 6)}.webm`;
      document.body.appendChild(a);
      a.click();
      document.body.removeChild(a);
      URL.revokeObjectURL(url);
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
            <div className="flex items-center gap-1.5">
              <h3 className="text-sm font-bold">Ghi âm Bảo mật</h3>
              <span className="text-[10px] px-1.5 py-0.2 rounded bg-rose-500/20 text-rose-400 font-mono">
                MIC
              </span>
            </div>
            <p className="text-[10px] text-zinc-400">Mã hóa trực tiếp vào Thư mục Vault</p>
          </div>
        </div>
      </div>

      {/* Recording Studio Box */}
      <div className="p-6 bg-gradient-to-b from-[#141e21] to-[#0d1416] border-b border-zinc-800 flex flex-col items-center justify-center space-y-4 shrink-0">
        {/* Animated Waveform Indicator */}
        <div className="flex items-center gap-1.5 h-12">
          {Array.from({ length: 16 }).map((_, i) => (
            <div
              key={i}
              className={`w-1.5 rounded-full transition-all duration-150 ${
                isRecording
                  ? 'bg-rose-500 animate-pulse'
                  : 'bg-zinc-700 h-2'
              }`}
              style={{
                height: isRecording ? `${Math.max(8, ((i * 17 + recordingSeconds * 19) % 48))}px` : '6px',
              }}
            />
          ))}
        </div>

        {/* Timer */}
        <div className="text-3xl font-mono font-bold tracking-wider text-white">
          {formatTimer(recordingSeconds)}
        </div>

        {/* Big Record Button */}
        <div>
          {isRecording ? (
            <button
              onClick={stopRecording}
              className="w-16 h-16 rounded-full bg-rose-600 hover:bg-rose-500 text-white flex items-center justify-center shadow-lg active:scale-95 transition-all"
              title="Dừng và lưu ghi âm"
            >
              <Square className="w-6 h-6 fill-current" />
            </button>
          ) : (
            <button
              onClick={startRecording}
              className="w-16 h-16 rounded-full bg-teal-500 hover:bg-teal-400 text-zinc-950 flex items-center justify-center shadow-lg active:scale-95 transition-all"
              title="Bắt đầu ghi âm"
            >
              <Mic className="w-7 h-7" />
            </button>
          )}
        </div>
        <span className="text-xs text-zinc-400">
          {isRecording ? 'Đang ghi âm bí mật...' : 'Nhấn nút để bắt đầu thu âm'}
        </span>
      </div>

      {/* Recordings List */}
      <div className="flex-1 overflow-y-auto p-4 space-y-2.5">
        <h4 className="text-xs font-bold uppercase tracking-wider text-zinc-400 px-1">
          Bản ghi âm đã lưu ({recordings.length})
        </h4>

        {recordings.length === 0 ? (
          <div className="py-12 text-center text-xs text-zinc-500">
            Chưa có bản ghi âm bảo mật nào.
          </div>
        ) : (
          recordings.map((rec) => {
            const isPlaying = activePlayId === rec.id;
            return (
              <div
                key={rec.id}
                className="p-3.5 rounded-2xl bg-[#141e21] border border-zinc-800 flex items-center justify-between shadow-xs hover:border-zinc-700 transition-all"
              >
                <div className="flex items-center gap-3 min-w-0">
                  <button
                    onClick={() => handlePlayAudio(rec)}
                    className={`w-10 h-10 rounded-full flex items-center justify-center shrink-0 transition-colors ${
                      isPlaying
                        ? 'bg-teal-500 text-zinc-950 shadow-md'
                        : 'bg-zinc-800 text-zinc-300 hover:bg-zinc-700'
                    }`}
                  >
                    {isPlaying ? <Pause className="w-4 h-4 fill-current" /> : <Play className="w-4 h-4 fill-current ml-0.5" />}
                  </button>
                  <div className="min-w-0">
                    <h5 className="text-xs font-bold truncate text-white">
                      {rec.name}
                    </h5>
                    <p className="text-[10px] text-zinc-400 font-mono mt-0.5">
                      {rec.duration ? `Thời lượng: ${rec.duration} · ` : ''}
                      {new Date(rec.createdAt).toLocaleDateString()}
                    </p>
                  </div>
                </div>

                <div className="flex items-center gap-1.5 shrink-0">
                  <button
                    onClick={() => handleExport(rec)}
                    className="p-2 rounded-xl text-zinc-400 hover:text-white hover:bg-zinc-800"
                    title="Xuất file âm thanh"
                  >
                    <Download className="w-4 h-4" />
                  </button>
                  <button
                    onClick={() => handleDelete(rec)}
                    className="p-2 rounded-xl text-zinc-400 hover:text-rose-400 hover:bg-zinc-800"
                    title="Xóa"
                  >
                    <Trash2 className="w-4 h-4" />
                  </button>
                </div>
              </div>
            );
          })
        )}
      </div>

      {toast && (
        <div className="p-3 bg-teal-500 text-zinc-950 font-bold text-xs flex items-center justify-center gap-1.5 shadow-xl animate-in fade-in">
          <CheckCircle2 className="w-4 h-4" />
          <span>{toast}</span>
        </div>
      )}
    </div>
  );
};
