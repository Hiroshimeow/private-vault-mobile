import React, { useState, useEffect } from 'react';
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
} from 'lucide-react';
import { LocalVaultRepository } from '../../vault/vaultRepository';
import { VaultItem } from '../../../types';

interface SecureFilesAppViewProps {
  onBack: () => void;
  repository: LocalVaultRepository;
}

export const SecureFilesAppView: React.FC<SecureFilesAppViewProps> = ({
  onBack,
  repository,
}) => {
  const [items, setItems] = useState<VaultItem[]>([]);
  const [selectedCategory, setSelectedCategory] = useState<string>('all');
  const [searchQuery, setSearchQuery] = useState('');

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

  const handleExport = async (item: VaultItem) => {
    try {
      const data = await repository.readBytes(item.id);
      const mime =
        item.kind === 'image'
          ? 'image/png'
          : item.kind === 'video'
          ? 'video/mp4'
          : item.kind === 'note'
          ? 'text/plain'
          : 'application/octet-stream';
      const blob = new Blob([data.bytes], { type: mime });
      const url = URL.createObjectURL(blob);
      const a = document.createElement('a');
      a.href = url;
      a.download = data.name || `vault-file-${item.id.slice(0, 6)}`;
      document.body.appendChild(a);
      a.click();
      document.body.removeChild(a);
      URL.revokeObjectURL(url);
    } catch {
      alert('Lỗi xuất tệp');
    }
  };

  const handleDelete = async (item: VaultItem) => {
    if (!window.confirm(`Xóa vĩnh viễn "${item.name}"?`)) return;
    await repository.delete(item.id);
    await loadFiles();
  };

  return (
    <div className="flex flex-col h-full bg-[#f8f9fa] dark:bg-[#121416] text-zinc-900 dark:text-zinc-100 select-none overflow-hidden font-sans">
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
      </div>

      {/* Search Bar */}
      <div className="px-3.5 py-2 bg-white dark:bg-[#181a1d] border-b border-zinc-200 dark:border-zinc-800 flex items-center gap-2 shrink-0">
        <Search className="w-4 h-4 text-zinc-400" />
        <input
          type="text"
          value={searchQuery}
          onChange={(e) => setSearchQuery(e.target.value)}
          placeholder="Tìm kiếm tệp..."
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
            className="h-full bg-amber-500 rounded-full"
            style={{ width: `${Math.min(100, (totalBytes / (512 * 1024 * 1024)) * 100 + 5)}%` }}
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
          <span className="text-[10px]">Tất cả</span>
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
          <span className="text-[10px]">Hình ảnh</span>
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
          <span className="text-[10px]">Video</span>
        </button>
        <button
          onClick={() => setSelectedCategory('note')}
          className={`p-2 rounded-xl text-center transition-all ${
            selectedCategory === 'note'
              ? 'bg-amber-500/10 border border-amber-500/30 text-amber-600 dark:text-amber-400 font-bold'
              : 'text-zinc-500 hover:bg-zinc-100 dark:hover:bg-zinc-800'
          }`}
        >
          <FileText className="w-4 h-4 mx-auto mb-1" />
          <span className="text-[10px]">Ghi chú</span>
        </button>
      </div>

      {/* Files List */}
      <div className="flex-1 overflow-y-auto p-3 space-y-2">
        {filtered.length === 0 ? (
          <div className="py-20 text-center text-xs text-zinc-400">Không có tệp nào trong mục này.</div>
        ) : (
          filtered.map((item) => (
            <div
              key={item.id}
              className="p-3 rounded-2xl bg-white dark:bg-[#181a1d] border border-zinc-200/80 dark:border-zinc-800 flex items-center justify-between shadow-xs hover:border-amber-400 transition-all"
            >
              <div className="flex items-center gap-3 min-w-0">
                <div className="w-9 h-9 rounded-xl bg-zinc-100 dark:bg-zinc-800 flex items-center justify-center shrink-0 text-amber-600">
                  {item.kind === 'image' ? (
                    <ImageIcon className="w-4 h-4" />
                  ) : item.kind === 'video' ? (
                    <Video className="w-4 h-4" />
                  ) : item.kind === 'note' ? (
                    <FileText className="w-4 h-4" />
                  ) : (
                    <File className="w-4 h-4" />
                  )}
                </div>
                <div className="min-w-0">
                  <h4 className="text-xs font-semibold truncate max-w-[170px]">
                    {item.name || 'Tệp bảo mật'}
                  </h4>
                  <p className="text-[10px] text-zinc-400 mt-0.5">
                    {new Date(item.createdAt).toLocaleDateString()} ·{' '}
                    {item.size ? `${(item.size / 1024).toFixed(1)} KB` : 'Mã hóa'}
                  </p>
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
