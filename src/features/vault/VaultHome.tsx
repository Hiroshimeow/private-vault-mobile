import React, { useState, useEffect, useRef } from 'react';
import {
  FileText,
  Image as ImageIcon,
  Video,
  File,
  Lock,
  Plus,
  Camera,
  Trash2,
  Share2,
  X,
  ChevronRight,
  AlertCircle,
  FilePlus,
} from 'lucide-react';
import { LocalVaultRepository } from './vaultRepository';
import { VaultItem, VaultItemKind } from '../../types';

interface VaultHomeProps {
  repository: LocalVaultRepository;
  confirmExport: boolean;
}

export const VaultHome: React.FC<VaultHomeProps> = ({ repository, confirmExport }) => {
  const [items, setItems] = useState<VaultItem[]>([]);
  const [busy, setBusy] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const [isNoteDialogOpen, setIsNoteDialogOpen] = useState(false);
  const [noteDraft, setNoteDraft] = useState('');

  const [isCameraOpen, setIsCameraOpen] = useState(false);
  const videoRef = useRef<HTMLVideoElement | null>(null);
  const streamRef = useRef<MediaStream | null>(null);

  const fileInputRef = useRef<HTMLInputElement | null>(null);

  const [selectedItem, setSelectedItem] = useState<VaultItem | null>(null);
  const [decryptedData, setDecryptedData] = useState<{
    bytes: Uint8Array;
    kind: VaultItemKind;
    name: string;
    createdAt: string;
  } | null>(null);
  const [previewUrl, setPreviewUrl] = useState<string | null>(null);
  const [previewError, setPreviewError] = useState<string | null>(null);

  const [confirmDialog, setConfirmDialog] = useState<{
    type: 'delete' | 'export';
    item: VaultItem;
  } | null>(null);

  const reload = async () => {
    try {
      const list = await repository.list();
      setItems(list);
      setError(null);
    } catch {
      setError('Protected items could not be loaded.');
    } finally {
      setBusy(false);
    }
  };

  useEffect(() => {
    reload();
  }, [repository]);

  const handleFileImport = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file) return;

    setBusy(true);
    try {
      const buffer = await file.arrayBuffer();
      const bytes = new Uint8Array(buffer);
      const kind = getKindFromFileName(file.name);
      await repository.addBytes(bytes, { kind, name: file.name });
      await reload();
    } catch (err) {
      console.error(err);
      setError('Failed to encrypt and store file.');
    } finally {
      setBusy(false);
      if (fileInputRef.current) fileInputRef.current.value = '';
    }
  };

  const startCamera = async () => {
    setIsCameraOpen(true);
    try {
      const stream = await navigator.mediaDevices.getUserMedia({
        video: { facingMode: 'user' },
      });
      streamRef.current = stream;
      if (videoRef.current) {
        videoRef.current.srcObject = stream;
        videoRef.current.play();
      }
    } catch (err) {
      console.warn('Camera access unavailable or denied:', err);
      if (fileInputRef.current) {
        fileInputRef.current.click();
      }
      setIsCameraOpen(false);
    }
  };

  const stopCamera = () => {
    if (streamRef.current) {
      streamRef.current.getTracks().forEach((track) => track.stop());
      streamRef.current = null;
    }
    setIsCameraOpen(false);
  };

  const capturePhoto = async () => {
    if (!videoRef.current) return;
    const canvas = document.createElement('canvas');
    canvas.width = videoRef.current.videoWidth || 640;
    canvas.height = videoRef.current.videoHeight || 480;
    const ctx = canvas.getContext('2d');
    if (!ctx) return;
    ctx.drawImage(videoRef.current, 0, 0, canvas.width, canvas.height);

    canvas.toBlob(async (blob) => {
      if (!blob) return;
      const buffer = await blob.arrayBuffer();
      stopCamera();
      setBusy(true);
      try {
        await repository.addBytes(new Uint8Array(buffer), {
          kind: 'image',
          name: `photo-${Date.now()}.png`,
        });
        await reload();
      } catch {
        setError('Failed to encrypt captured photo.');
      } finally {
        setBusy(false);
      }
    }, 'image/png');
  };

  const handleSaveNote = async () => {
    const trimmed = noteDraft.trim();
    if (!trimmed) return;
    setBusy(true);
    setIsNoteDialogOpen(false);
    try {
      const bytes = new TextEncoder().encode(trimmed);
      await repository.addBytes(bytes, { kind: 'note', name: 'Secure Note' });
      setNoteDraft('');
      await reload();
    } catch {
      setError('Failed to encrypt note.');
    } finally {
      setBusy(false);
    }
  };

  const handleOpenItem = async (item: VaultItem) => {
    setSelectedItem(item);
    setPreviewError(null);
    try {
      const data = await repository.readBytes(item.id);
      setDecryptedData(data);
      if (data.kind === 'image' || data.kind === 'video') {
        const mime = data.kind === 'image' ? 'image/png' : 'video/mp4';
        const blob = new Blob([data.bytes], { type: mime });
        const url = URL.createObjectURL(blob);
        setPreviewUrl(url);
      } else {
        setPreviewUrl(null);
      }
    } catch {
      setPreviewError('Item could not be decrypted.');
    }
  };

  const closePreview = () => {
    if (previewUrl) {
      URL.revokeObjectURL(previewUrl);
      setPreviewUrl(null);
    }
    setSelectedItem(null);
    setDecryptedData(null);
  };

  const handleDelete = async (item: VaultItem) => {
    await repository.delete(item.id);
    closePreview();
    setConfirmDialog(null);
    await reload();
  };

  const handleExport = (item: VaultItem) => {
    if (confirmExport) {
      setConfirmDialog({ type: 'export', item });
    } else {
      executeExport(item);
    }
  };

  const executeExport = async (item: VaultItem) => {
    try {
      const data = await repository.readBytes(item.id);
      const mime =
        data.kind === 'image'
          ? 'image/png'
          : data.kind === 'note'
          ? 'text/plain'
          : 'application/octet-stream';
      const blob = new Blob([data.bytes], { type: mime });
      const url = URL.createObjectURL(blob);
      const a = document.createElement('a');
      a.href = url;
      a.download = data.name || `private-item-${item.id.slice(0, 8)}.bin`;
      document.body.appendChild(a);
      a.click();
      document.body.removeChild(a);
      URL.revokeObjectURL(url);
    } catch {
      alert('Failed to export item.');
    } finally {
      setConfirmDialog(null);
    }
  };

  const getKindFromFileName = (name: string): VaultItemKind => {
    const lower = name.toLowerCase();
    if (/\.(jpg|jpeg|png|gif|webp|svg)$/.test(lower)) return 'image';
    if (/\.(mp4|mov|webm|mkv)$/.test(lower)) return 'video';
    if (/\.(txt|md)$/.test(lower)) return 'note';
    return 'document';
  };

  const getIcon = (kind: VaultItemKind) => {
    switch (kind) {
      case 'note':
        return <FileText className="w-5 h-5 text-teal-600 dark:text-teal-400" />;
      case 'image':
        return <ImageIcon className="w-5 h-5 text-emerald-600 dark:text-emerald-400" />;
      case 'video':
        return <Video className="w-5 h-5 text-sky-600 dark:text-sky-400" />;
      case 'document':
        return <File className="w-5 h-5 text-amber-600 dark:text-amber-400" />;
      default:
        return <Lock className="w-5 h-5 text-zinc-400" />;
    }
  };

  const formatKindLabel = (kind: VaultItemKind) => {
    switch (kind) {
      case 'note':
        return 'Protected Note';
      case 'image':
        return 'Protected Image';
      case 'video':
        return 'Protected Video';
      case 'document':
        return 'Protected Document';
      default:
        return 'Protected Item';
    }
  };

  const formatDate = (iso: string) => {
    try {
      const d = new Date(iso);
      return `${d.toLocaleDateString()} ${d.toLocaleTimeString([], {
        hour: '2-digit',
        minute: '2-digit',
      })}`;
    } catch {
      return iso;
    }
  };

  return (
    <div className="flex flex-col h-full bg-zinc-50 dark:bg-[#101718] overflow-hidden">
      <input
        type="file"
        ref={fileInputRef}
        onChange={handleFileImport}
        className="hidden"
      />

      <div className="p-4 border-b border-zinc-200/80 dark:border-zinc-800">
        <div className="grid grid-cols-3 gap-2">
          <button
            onClick={() => fileInputRef.current?.click()}
            data-testid="vault-import"
            className="flex items-center justify-center gap-1.5 py-2.5 px-3 rounded-xl bg-[#315e63] dark:bg-[#78aeb3] text-white dark:text-zinc-950 font-medium text-xs shadow-xs hover:opacity-90 active:scale-95 transition-all"
          >
            <Plus className="w-4 h-4" />
            <span>Import</span>
          </button>
          <button
            onClick={startCamera}
            data-testid="vault-camera"
            className="flex items-center justify-center gap-1.5 py-2.5 px-3 rounded-xl border border-zinc-200 dark:border-zinc-700 bg-white dark:bg-zinc-900 text-zinc-800 dark:text-zinc-100 font-medium text-xs hover:bg-zinc-100 dark:hover:bg-zinc-800 active:scale-95 transition-all"
          >
            <Camera className="w-4 h-4" />
            <span>Camera</span>
          </button>
          <button
            onClick={() => setIsNoteDialogOpen(true)}
            data-testid="vault-new-note"
            className="flex items-center justify-center gap-1.5 py-2.5 px-3 rounded-xl border border-zinc-200 dark:border-zinc-700 bg-white dark:bg-zinc-900 text-zinc-800 dark:text-zinc-100 font-medium text-xs hover:bg-zinc-100 dark:hover:bg-zinc-800 active:scale-95 transition-all"
          >
            <FilePlus className="w-4 h-4" />
            <span>Note</span>
          </button>
        </div>
      </div>

      <div className="px-5 py-3 flex items-center justify-between text-xs text-zinc-500 dark:text-zinc-400">
        <span className="font-semibold uppercase tracking-wider text-[11px]">Protected Items</span>
        <span>{items.length} items</span>
      </div>

      <div className="flex-1 overflow-y-auto px-4 pb-6 space-y-2">
        {busy ? (
          <div className="flex flex-col items-center justify-center py-20 text-zinc-400 gap-2">
            <div className="w-6 h-6 border-2 border-[#315e63] border-t-transparent rounded-full animate-spin" />
            <span className="text-xs">Accessing encrypted storage...</span>
          </div>
        ) : error ? (
          <div className="flex flex-col items-center justify-center py-16 text-center text-rose-500 gap-2">
            <AlertCircle className="w-8 h-8" />
            <p className="text-sm font-medium">{error}</p>
          </div>
        ) : items.length === 0 ? (
          <div className="flex flex-col items-center justify-center py-20 text-center text-zinc-400 gap-3">
            <div className="w-16 h-16 rounded-full bg-zinc-100 dark:bg-zinc-900 flex items-center justify-center">
              <Lock className="w-8 h-8 text-zinc-300 dark:text-zinc-600" />
            </div>
            <div>
              <p className="text-sm font-medium text-zinc-700 dark:text-zinc-300">Vault is empty</p>
              <p className="text-xs text-zinc-400 mt-1 max-w-xs">
                Import media, capture photos, or write encrypted notes stored only in this vault.
              </p>
            </div>
          </div>
        ) : (
          items.map((item) => (
            <div
              key={item.id}
              onClick={() => handleOpenItem(item)}
              className="flex items-center justify-between p-3.5 rounded-2xl bg-white dark:bg-zinc-900 border border-zinc-200/80 dark:border-zinc-800/80 hover:border-zinc-300 dark:hover:border-zinc-700 cursor-pointer shadow-xs transition-all active:scale-[0.99]"
            >
              <div className="flex items-center gap-3">
                <div className="w-10 h-10 rounded-xl bg-zinc-100 dark:bg-zinc-800 flex items-center justify-center shrink-0">
                  {getIcon(item.kind)}
                </div>
                <div className="min-w-0">
                  <div className="text-sm font-medium text-zinc-900 dark:text-zinc-100 truncate">
                    {item.name || formatKindLabel(item.kind)}
                  </div>
                  <div className="text-xs text-zinc-400 mt-0.5">
                    {formatDate(item.createdAt)}
                    {item.size ? ` · ${(item.size / 1024).toFixed(1)} KB` : ''}
                  </div>
                </div>
              </div>
              <ChevronRight className="w-4 h-4 text-zinc-400 shrink-0" />
            </div>
          ))
        )}
      </div>

      {isNoteDialogOpen && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/60 p-4 backdrop-blur-xs">
          <div className="w-full max-w-md bg-white dark:bg-zinc-900 rounded-3xl p-6 shadow-2xl border border-zinc-200 dark:border-zinc-800 flex flex-col gap-4">
            <h3 className="text-lg font-bold text-zinc-900 dark:text-zinc-100">
              New Protected Note
            </h3>
            <textarea
              data-testid="vault-note-input"
              rows={6}
              value={noteDraft}
              onChange={(e) => setNoteDraft(e.target.value)}
              placeholder="Write a note stored only in the encrypted vault..."
              className="w-full p-3 rounded-xl border border-zinc-200 dark:border-zinc-700 bg-zinc-50 dark:bg-zinc-950 text-zinc-900 dark:text-zinc-100 text-sm focus:outline-none focus:ring-2 focus:ring-[#315e63]"
              maxLength={20000}
            />
            <div className="flex justify-end gap-2">
              <button
                type="button"
                onClick={() => setIsNoteDialogOpen(false)}
                className="px-4 py-2 rounded-xl text-sm font-medium text-zinc-600 dark:text-zinc-400 hover:bg-zinc-100 dark:hover:bg-zinc-800"
              >
                Cancel
              </button>
              <button
                type="button"
                onClick={handleSaveNote}
                disabled={!noteDraft.trim()}
                className="px-5 py-2 rounded-xl text-sm font-semibold bg-[#315e63] dark:bg-[#78aeb3] text-white dark:text-zinc-950 disabled:opacity-40"
              >
                Save
              </button>
            </div>
          </div>
        </div>
      )}

      {isCameraOpen && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/80 p-4">
          <div className="w-full max-w-md bg-zinc-900 rounded-3xl overflow-hidden shadow-2xl flex flex-col">
            <div className="p-4 flex justify-between items-center text-white">
              <span className="font-medium text-sm">Camera Capture</span>
              <button onClick={stopCamera} className="p-1 rounded-full hover:bg-zinc-800">
                <X className="w-5 h-5" />
              </button>
            </div>
            <div className="relative bg-black aspect-4/3 flex items-center justify-center overflow-hidden">
              <video ref={videoRef} playsInline autoPlay className="w-full h-full object-cover" />
            </div>
            <div className="p-4 flex justify-center gap-4 bg-zinc-950">
              <button
                onClick={capturePhoto}
                className="w-16 h-16 rounded-full border-4 border-white flex items-center justify-center hover:bg-white/20 transition-all"
              >
                <div className="w-12 h-12 rounded-full bg-white" />
              </button>
            </div>
          </div>
        </div>
      )}

      {selectedItem && (
        <div className="fixed inset-0 z-50 flex items-end sm:items-center justify-center bg-black/60 backdrop-blur-xs p-0 sm:p-4">
          <div className="w-full max-w-md bg-white dark:bg-[#172021] rounded-t-3xl sm:rounded-3xl shadow-2xl border border-zinc-200 dark:border-zinc-800 p-5 flex flex-col gap-4 max-h-[85vh]">
            <div className="flex items-center justify-between pb-2 border-b border-zinc-200 dark:border-zinc-800">
              <div className="flex items-center gap-2">
                {getIcon(selectedItem.kind)}
                <span className="font-semibold text-sm text-zinc-900 dark:text-zinc-100 truncate max-w-[220px]">
                  {selectedItem.name || formatKindLabel(selectedItem.kind)}
                </span>
              </div>
              <button onClick={closePreview} className="text-zinc-400 hover:text-zinc-600">
                <X className="w-5 h-5" />
              </button>
            </div>

            {previewError ? (
              <div className="py-8 text-center text-sm text-rose-500">{previewError}</div>
            ) : !decryptedData ? (
              <div className="py-8 text-center text-xs text-zinc-400">Decrypting item...</div>
            ) : (
              <div className="overflow-y-auto max-h-[50vh] flex flex-col items-center justify-center my-2">
                {decryptedData.kind === 'image' && previewUrl ? (
                  <img
                    src={previewUrl}
                    alt="Protected vault image"
                    className="max-h-72 rounded-xl object-contain shadow-xs"
                  />
                ) : decryptedData.kind === 'note' ? (
                  <div className="w-full p-4 rounded-xl bg-zinc-50 dark:bg-zinc-900 font-sans text-sm whitespace-pre-wrap text-zinc-800 dark:text-zinc-200">
                    {new TextDecoder().decode(decryptedData.bytes)}
                  </div>
                ) : (
                  <div className="p-8 text-center text-zinc-500">
                    <File className="w-12 h-12 mx-auto mb-2 text-zinc-400" />
                    <p className="text-sm font-medium">{decryptedData.name}</p>
                    <p className="text-xs text-zinc-400 mt-1">
                      {decryptedData.bytes.byteLength} protected bytes
                    </p>
                  </div>
                )}
              </div>
            )}

            <div className="grid grid-cols-2 gap-3 pt-2">
              <button
                type="button"
                onClick={() => setConfirmDialog({ type: 'delete', item: selectedItem })}
                className="py-2.5 rounded-xl border border-rose-200 dark:border-rose-900/60 text-rose-600 dark:text-rose-400 font-medium text-xs hover:bg-rose-50 dark:hover:bg-rose-950/40 flex items-center justify-center gap-1.5 transition-colors"
              >
                <Trash2 className="w-4 h-4" />
                Delete
              </button>
              <button
                type="button"
                onClick={() => handleExport(selectedItem)}
                className="py-2.5 rounded-xl bg-[#315e63] dark:bg-[#78aeb3] text-white dark:text-zinc-950 font-medium text-xs hover:opacity-95 flex items-center justify-center gap-1.5 transition-opacity"
              >
                <Share2 className="w-4 h-4" />
                Export
              </button>
            </div>
          </div>
        </div>
      )}

      {confirmDialog && (
        <div className="fixed inset-0 z-60 flex items-center justify-center bg-black/60 p-4 backdrop-blur-xs">
          <div className="w-full max-w-sm bg-white dark:bg-zinc-900 rounded-3xl p-6 shadow-2xl border border-zinc-200 dark:border-zinc-800 flex flex-col gap-3">
            <h4 className="font-bold text-base text-zinc-900 dark:text-zinc-100">
              {confirmDialog.type === 'delete' ? 'Delete from vault?' : 'Export this item?'}
            </h4>
            <p className="text-xs text-zinc-500 dark:text-zinc-400 leading-relaxed">
              {confirmDialog.type === 'delete'
                ? 'This removes the app copy. Flash storage does not guarantee forensic secure erase.'
                : 'The exported copy leaves protected app storage and may be visible to other apps.'}
            </p>
            <div className="flex justify-end gap-2 pt-2">
              <button
                type="button"
                onClick={() => setConfirmDialog(null)}
                className="px-4 py-2 rounded-xl text-xs font-medium text-zinc-600 dark:text-zinc-400 hover:bg-zinc-100 dark:hover:bg-zinc-800"
              >
                Cancel
              </button>
              <button
                type="button"
                onClick={() =>
                  confirmDialog.type === 'delete'
                    ? handleDelete(confirmDialog.item)
                    : executeExport(confirmDialog.item)
                }
                className={`px-4 py-2 rounded-xl text-xs font-semibold text-white ${
                  confirmDialog.type === 'delete'
                    ? 'bg-rose-600 hover:bg-rose-700'
                    : 'bg-[#315e63] hover:opacity-90'
                }`}
              >
                {confirmDialog.type === 'delete' ? 'Delete' : 'Export'}
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
};
