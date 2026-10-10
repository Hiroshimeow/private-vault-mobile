import React, { useState, useEffect, useRef } from 'react';
import {
  ChevronLeft,
  Folder,
  File,
  Image as ImageIcon,
  Video,
  FileText,
  Download,
  Trash2,
  HardDrive,
  Search,
  Plus,
  Music,
} from 'lucide-react';
import { LocalVaultRepository } from '../../vault/vaultRepository';
import { VaultItem } from '../../../types';

interface SecureFilesAppViewProps {
  onBack: () => void;
  repository: LocalVaultRepository;
  confirmExport?: boolean;
}

export const SecureFilesAppView: React.FC<SecureFilesAppViewProps> = ({
  onBack,
  repository,
  confirmExport = true,
}) => {
  const [items, setItems] = useState<VaultItem[]>([]);
  const [selectedCategory, setSelectedCategory] = useState<string>('all');
  const [searchQuery, setSearchQuery] = useState('');
  const [isImporting, setIsImporting] = useState(false);
  const fileInputRef = useRef<HTMLInputElement | null>(null);

  const loadFiles = async () => {
    try {
      const all = await repository.list();
      setItems(all);
    } catch (e) {
      console.error(e);
    }
  };

  useEffect(() => {
    loadFiles();
  }, [repository]);

  const totalBytes = items.reduce((acc, i) => acc + (i.size || 2048), 0);

  const filtered = items.filter((i) => {
    if (selectedCategory !== 'all' && i.kind !== selectedCategory) return false;
    if (searchQuery.trim() && !i.name?.toLowerCase().includes(searchQuery.toLowerCase())) {
      return false;
    }
    return true;
  });

  const handleImportFile = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const files = e.target.files;
    if (!files || files.length === 0) return;
    setIsImporting(true);

    try {
      for (let i = 0; i < files.length; i++) {
        const file = files[i];
        const buffer = await file.arrayBuffer();
        const bytes = new Uint8Array(buffer);

        let kind: VaultItem['kind'] = 'document';
        if (file.type.startsWith('image/')) kind = 'image';
        else if (file.type.startsWith('video/')) kind = 'video';
        else if (file.type.startsWith('audio/')) kind = 'audio';
        else if (file.name.endsWith('.txt') || file.name.endsWith('.md')) kind = 'note';

        await repository.addBytes(bytes, {
          kind,
          name: file.name,
          mimeType: file.type || 'application/octet-stream',
          album: 'Tệp tải lên',
        });
      }
      await loadFiles();
    } catch (err) {
      alert('Lỗi nhập tệp: ' + (err instanceof Error ? err.message : String(err)));
    } finally {
      setIsImporting(false);
      if (fileInputRef.current) fileInputRef.current.value = '';
    }
  };

  const handleExport = async (item: VaultItem) => {
    if (confirmExport) {
      const ok = window.confirm(
        `Bạn có chắc chắn muốn xuất tệp "${item.name}" ra bộ nhớ máy không? Tệp sau khi xuất sẽ không còn được bảo vệ bởi Vault.`
      );
      if (!ok) return;
    }

    try {
      const data = await repository.readBytes(item.id);
      const ext = (item.name || '').split('.').pop()?.toLowerCase();
      const mimeMap: Record<string, string> = {
        jpg: 'image/jpeg',
        jpeg: 'image/jpeg',
        png: 'image/png',
        webp: 'image/webp',
        pdf: 'application/pdf',
        txt: 'text/plain',
        mp4: 'video/mp4',
        webm: 'video/webm',
        m4a: 'audio/mp4',
      };
      const mime =
        data.mimeType ||
        (ext ? mimeMap[ext] : null) ||
        (item.kind === 'note' ? 'text/plain' : 'application/octet-stream');

      const blob = new Blob([data.bytes], { type: mime });
      const url = URL.createObjectURL(blob);
      const a = document.createElement('a');
      a.href = url;
      a.download = data.name || `vault-file-${item.id.slice(0, 6)}`;
      document.body.appendChild(a);
      a.click();
      document.body.removeChild(a);
      setTimeout(() => URL.revokeObjectURL(url), 1000);
    } catch {
      alert('Lỗi xuất tệp');
    }
  };

  const handleDelete = async (item: VaultItem) => {
    if (!window.confirm(`Xóa vĩnh viễn "${item.name}" khỏi Vault?`)) return;
    await repository.delete(item.id);
    await loadFiles();
  };

  const getFileIcon = (kind: VaultItem['kind']) => {
    switch (kind) {
      case 'image':
        return <ImageIcon className="w-5 h-5 text-teal-500" />;
      case 'video':
        return <Video className="w-5 h-5 text-blue-500" />;
      case 'audio':
        return <Music className="w-5 h-5 text-purple-500" />;
      case 'note':
        return <FileText className="w-5 h-5 text-amber-500" />;
      default:
        return <File className="w-5 h-5 text-zinc-400" />;
    }
  };

  return (
    <div className="flex flex-col h-full bg-[#f8f9fa] dark:bg-[#121416] text-zinc-900 dark:text-zinc-100 select-none overflow-hidden font-sans">
      <input
        type="file"
        ref={fileInputRef}
        onChange={handleImportFile}
        multiple
        className="hidden"
      />

      {/* Header */}
      <div className="bg-amber-600 text-white px-3.5 py-3 flex items-center justify-between shadow-md shrink-0">
        <div className="flex items-center gap-2.5">
          <button onClick={onBack} className="p-1 rounded-full hover:bg-white/20">
            <ChevronLeft className="w-5 h-5" />
          </button>
          <div>
            <h3 className="text-sm font-bold">File của bạn (My Files)</h3>
            <p className="text-[10px] text-white/80">Quản lý tệp mã hóa Thư mục Bảo mật</p>
          </div>
        </div>

        <button
          onClick={() => fileInputRef.current?.click()}
          disabled={isImporting}
          className="flex items-center gap-1.5 px-3 py-1.5 rounded-xl bg-white/20 hover:bg-white/30 text-white text-xs font-semibold"
        >
          <Plus className="w-4 h-4" />
          <span>{isImporting ? 'Đang nhập...' : 'Nhập tệp'}</span>
        </button>
      </div>

      {/* Search Bar */}
      <div className="px-3.5 py-2 bg-white dark:bg-[#181a1d] border-b border-zinc-200 dark:border-zinc-800 flex items-center gap-2 shrink-0">
        <Search className="w-4 h-4 text-zinc-400" />
        <input
          type="text"
          value={searchQuery}
          onChange={(e) => setSearchQuery(e.target.value)}
          placeholder="Tìm kiếm tệp mã hóa..."
          className="flex-1 bg-transparent text-xs text-zinc-900 dark:text-zinc-100 placeholder-zinc-400 focus:outline-none"
        />
      </div>

      {/* Storage meter */}
      <div className="p-3.5 bg-white dark:bg-[#181a1d] border-b border-zinc-200 dark:border-zinc-800 shrink-0 space-y-2">
        <div className="flex items-center justify-between text-xs font-semibold">
          <span className="flex items-center gap-1.5 text-zinc-700 dark:text-zinc-300">
            <HardDrive className="w-4 h-4 text-amber-500" />
            <span>Bộ nhớ Thư mục Bảo mật</span>
          </span>
          <span className="font-mono text-zinc-500 text-[11px]">
            {(totalBytes / (1024 * 1024)).toFixed(2)} MB / 512 MB
          </span>
        </div>
        <div className="w-full h-2 rounded-full bg-zinc-200 dark:bg-zinc-700 overflow-hidden">
          <div
            className="h-full bg-amber-500 rounded-full transition-all"
            style={{ width: `${Math.min(100, (totalBytes / (512 * 1024 * 1024)) * 100 + 2)}%` }}
          />
        </div>
      </div>

      {/* Categories Grid */}
      <div className="p-3 grid grid-cols-4 gap-2 bg-white dark:bg-[#181a1d] border-b border-zinc-200 dark:border-zinc-800 shrink-0">
        <button
          onClick={() => setSelectedCategory('all')}
          className={`p-2 rounded-xl text-center transition-all ${
            selectedCategory === 'all'
              ? 'bg-amber-500/10 border border-amber-500/30 text-amber-600 dark:text-amber-400 font-bold'
              : 'text-zinc-500 hover:bg-zinc-100 dark:hover:bg-zinc-800'
          }`}
        >
          <Folder className="w-4 h-4 mx-auto mb-1" />
          <span className="text-[10px] block truncate">Tất cả ({items.length})</span>
        </button>
        <button
          onClick={() => setSelectedCategory('image')}
          className={`p-2 rounded-xl text-center transition-all ${
            selectedCategory === 'image'
              ? 'bg-amber-500/10 border border-amber-500/30 text-amber-600 dark:text-amber-400 font-bold'
              : 'text-zinc-500 hover:bg-zinc-100 dark:hover:bg-zinc-800'
          }`}
        >
          <ImageIcon className="w-4 h-4 mx-auto mb-1" />
          <span className="text-[10px] block truncate">Ảnh</span>
        </button>
        <button
          onClick={() => setSelectedCategory('video')}
          className={`p-2 rounded-xl text-center transition-all ${
            selectedCategory === 'video'
              ? 'bg-amber-500/10 border border-amber-500/30 text-amber-600 dark:text-amber-400 font-bold'
              : 'text-zinc-500 hover:bg-zinc-100 dark:hover:bg-zinc-800'
          }`}
        >
          <Video className="w-4 h-4 mx-auto mb-1" />
          <span className="text-[10px] block truncate">Video</span>
        </button>
        <button
          onClick={() => setSelectedCategory('document')}
          className={`p-2 rounded-xl text-center transition-all ${
            selectedCategory === 'document'
              ? 'bg-amber-500/10 border border-amber-500/30 text-amber-600 dark:text-amber-400 font-bold'
              : 'text-zinc-500 hover:bg-zinc-100 dark:hover:bg-zinc-800'
          }`}
        >
          <File className="w-4 h-4 mx-auto mb-1" />
          <span className="text-[10px] block truncate">Tài liệu</span>
        </button>
      </div>

      {/* Files List */}
      <div className="flex-1 overflow-y-auto p-3 space-y-2">
        {filtered.length === 0 ? (
          <div className="py-20 text-center text-zinc-400 text-xs">
            Không tìm thấy tệp nào trong mục này
          </div>
        ) : (
          filtered.map((item) => (
            <div
              key={item.id}
              className="p-3 rounded-xl bg-white dark:bg-[#181a1d] border border-zinc-200/80 dark:border-zinc-800 flex items-center justify-between shadow-xs hover:border-amber-500/50 transition-colors"
            >
              <div className="flex items-center gap-3 min-w-0">
                <div className="w-9 h-9 rounded-lg bg-zinc-100 dark:bg-zinc-800 flex items-center justify-center shrink-0">
                  {getFileIcon(item.kind)}
                </div>
                <div className="min-w-0">
                  <h4 className="text-xs font-bold text-zinc-900 dark:text-zinc-100 truncate">
                    {item.name || 'Tệp không tên'}
                  </h4>
                  <div className="flex items-center gap-2 text-[10px] text-zinc-400 mt-0.5">
                    <span>{((item.size || 1024) / 1024).toFixed(1)} KB</span>
                    <span>·</span>
                    <span>{new Date(item.createdAt).toLocaleDateString()}</span>
                  </div>
                </div>
              </div>

              <div className="flex items-center gap-1">
                <button
                  onClick={() => handleExport(item)}
                  className="p-1.5 text-zinc-400 hover:text-amber-500"
                  title="Xuất tệp"
                >
                  <Download className="w-4 h-4" />
                </button>
                <button
                  onClick={() => handleDelete(item)}
                  className="p-1.5 text-zinc-400 hover:text-rose-500"
                  title="Xóa tệp"
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
