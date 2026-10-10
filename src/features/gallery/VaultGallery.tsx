import React, { useState, useEffect, useRef, useMemo } from 'react';
import {
  Image as ImageIcon,
  Camera,
  Plus,
  Trash2,
  Share2,
  Heart,
  Info,
  X,
  ChevronLeft,
  ChevronRight,
  ZoomIn,
  ZoomOut,
  FolderPlus,
  Search,
  CheckSquare,
  Square,
  Sparkles,
  Play,
  Folder,
  Download,
} from 'lucide-react';
import { LocalVaultRepository } from '../vault/vaultRepository';
import { VaultItem } from '../../types';
import { seedSampleVaultMedia } from './sampleMedia';

interface VaultGalleryProps {
  repository: LocalVaultRepository;
  confirmExport?: boolean;
  onOpenApp?: (appId: string) => void;
}

export const VaultGallery: React.FC<VaultGalleryProps> = ({
  repository,
}) => {
  const [items, setItems] = useState<VaultItem[]>([]);
  const [loading, setLoading] = useState(true);
  const [activeTab, setActiveTab] = useState<'pictures' | 'albums' | 'videos' | 'favorites'>('pictures');
  const [selectedAlbum, setSelectedAlbum] = useState<string | null>(null);

  // Search & Filter
  const [searchQuery, setSearchQuery] = useState('');
  const [isSearchOpen, setIsSearchOpen] = useState(false);

  // Selection mode
  const [isSelectMode, setIsSelectMode] = useState(false);
  const [selectedIds, setSelectedIds] = useState<Set<string>>(new Set());

  // Lightbox / Viewer
  const [viewingIndex, setViewingIndex] = useState<number | null>(null);
  const [viewingDecryptedUrl, setViewingDecryptedUrl] = useState<string | null>(null);
  const [zoomLevel, setZoomLevel] = useState<number>(1);
  const [showInfoModal, setShowInfoModal] = useState(false);
  const [isSlideshowActive, setIsSlideshowActive] = useState(false);

  // Modals
  const [isCreateAlbumOpen, setIsCreateAlbumOpen] = useState(false);
  const [newAlbumName, setNewAlbumName] = useState('');
  const [isMoveAlbumOpen, setIsMoveAlbumOpen] = useState(false);
  const [targetMoveAlbum, setTargetMoveAlbum] = useState('');

  // Camera capture modal
  const [isCameraActive, setIsCameraActive] = useState(false);
  const videoRef = useRef<HTMLVideoElement | null>(null);
  const cameraStreamRef = useRef<MediaStream | null>(null);

  const fileInputRef = useRef<HTMLInputElement | null>(null);
  const [notification, setNotification] = useState<string | null>(null);

  const showToast = (msg: string) => {
    setNotification(msg);
    setTimeout(() => setNotification(null), 3000);
  };

  const loadMedia = async () => {
    try {
      setLoading(true);
      const all = await repository.list();
      // Filter for media items (images and videos) or all
      setItems(all.filter((i) => i.kind === 'image' || i.kind === 'video'));
    } catch (err) {
      console.error('Failed to load gallery items:', err);
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    loadMedia();
  }, [repository]);

  // If items empty on first load, seed with high quality sample media automatically
  useEffect(() => {
    if (!loading && items.length === 0) {
      seedSampleVaultMedia(repository).then(() => {
        loadMedia();
      });
    }
  }, [loading, items.length, repository]);

  // Decrypt media for lightbox viewing
  useEffect(() => {
    if (viewingIndex === null || viewingIndex < 0 || viewingIndex >= filteredItems.length) {
      if (viewingDecryptedUrl) {
        URL.revokeObjectURL(viewingDecryptedUrl);
        setViewingDecryptedUrl(null);
      }
      setZoomLevel(1);
      return;
    }

    const currentItem = filteredItems[viewingIndex];
    let isMounted = true;

    repository
      .readBytes(currentItem.id)
      .then((data) => {
        if (!isMounted) return;
        const mime = data.kind === 'video' ? 'video/mp4' : data.name.endsWith('.svg') ? 'image/svg+xml' : 'image/png';
        const blob = new Blob([data.bytes], { type: mime });
        const url = URL.createObjectURL(blob);
        if (viewingDecryptedUrl) URL.revokeObjectURL(viewingDecryptedUrl);
        setViewingDecryptedUrl(url);
      })
      .catch((err) => {
        console.error('Decryption failed for preview:', err);
        showToast('Không thể giải mã tệp này');
      });

    return () => {
      isMounted = false;
    };
  }, [viewingIndex]);

  // Slideshow timer
  useEffect(() => {
    if (!isSlideshowActive || viewingIndex === null) return;
    const interval = setInterval(() => {
      setViewingIndex((prev) => {
        if (prev === null) return null;
        return (prev + 1) % filteredItems.length;
      });
    }, 3000);
    return () => clearInterval(interval);
  }, [isSlideshowActive, viewingIndex]);

  // Keyboard navigation in lightbox
  useEffect(() => {
    const handleKeyDown = (e: KeyboardEvent) => {
      if (viewingIndex === null) return;
      if (e.key === 'ArrowRight') {
        setViewingIndex((prev) => (prev !== null && prev < filteredItems.length - 1 ? prev + 1 : 0));
      } else if (e.key === 'ArrowLeft') {
        setViewingIndex((prev) => (prev !== null && prev > 0 ? prev - 1 : filteredItems.length - 1));
      } else if (e.key === 'Escape') {
        setViewingIndex(null);
      }
    };
    window.addEventListener('keydown', handleKeyDown);
    return () => window.removeEventListener('keydown', handleKeyDown);
  }, [viewingIndex]);

  // File import
  const handleImportFile = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file) return;

    try {
      const buffer = await file.arrayBuffer();
      const bytes = new Uint8Array(buffer);
      const isVid = /\.(mp4|webm|mov|mkv)$/i.test(file.name);
      const album = selectedAlbum || 'Tải về';

      await repository.addBytes(bytes, {
        kind: isVid ? 'video' : 'image',
        name: file.name,
        album,
        isFavorite: false,
      });

      showToast(`Đã mã hóa và lưu "${file.name}" vào Thư mục Bảo mật`);
      await loadMedia();
    } catch (err) {
      console.error(err);
      showToast('Lỗi khi mã hóa tệp vào thư mục bảo mật');
    } finally {
      if (fileInputRef.current) fileInputRef.current.value = '';
    }
  };

  // Live Camera
  const startCamera = async () => {
    setIsCameraActive(true);
    try {
      const stream = await navigator.mediaDevices.getUserMedia({
        video: { facingMode: 'environment', width: { ideal: 1920 }, height: { ideal: 1080 } },
      });
      cameraStreamRef.current = stream;
      if (videoRef.current) {
        videoRef.current.srcObject = stream;
        videoRef.current.play();
      }
    } catch {
      try {
        const fallback = await navigator.mediaDevices.getUserMedia({ video: true });
        cameraStreamRef.current = fallback;
        if (videoRef.current) {
          videoRef.current.srcObject = fallback;
          videoRef.current.play();
        }
      } catch {
        showToast('Không có quyền truy cập máy ảnh');
        setIsCameraActive(false);
      }
    }
  };

  const stopCamera = () => {
    if (cameraStreamRef.current) {
      cameraStreamRef.current.getTracks().forEach((t) => t.stop());
      cameraStreamRef.current = null;
    }
    setIsCameraActive(false);
  };

  const capturePhoto = async () => {
    if (!videoRef.current) return;
    const canvas = document.createElement('canvas');
    canvas.width = videoRef.current.videoWidth || 1280;
    canvas.height = videoRef.current.videoHeight || 720;
    const ctx = canvas.getContext('2d');
    if (!ctx) return;
    ctx.drawImage(videoRef.current, 0, 0, canvas.width, canvas.height);

    canvas.toBlob(async (blob) => {
      if (!blob) return;
      const buffer = await blob.arrayBuffer();
      stopCamera();
      try {
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
        showToast('Ảnh chụp đã được mã hóa vào Album Máy ảnh bảo mật');
        await loadMedia();
      } catch {
        showToast('Lỗi khi lưu ảnh');
      }
    }, 'image/png');
  };

  // Toggle Favorite
  const handleToggleFavorite = async (item: VaultItem, e?: React.MouseEvent) => {
    if (e) e.stopPropagation();
    const nextFav = !item.isFavorite;
    await repository.updateMeta(item.id, { isFavorite: nextFav });
    setItems((prev) =>
      prev.map((i) => (i.id === item.id ? { ...i, isFavorite: nextFav } : i))
    );
    showToast(nextFav ? 'Đã thêm vào Mục yêu thích' : 'Đã xóa khỏi Mục yêu thích');
  };

  // Single Delete
  const handleDeleteItem = async (item: VaultItem) => {
    if (!window.confirm(`Xóa vĩnh viễn "${item.name}" khỏi Thư mục Bảo mật?`)) return;
    await repository.delete(item.id);
    setViewingIndex(null);
    showToast('Đã xóa tệp');
    await loadMedia();
  };

  // Batch Delete
  const handleBatchDelete = async () => {
    if (selectedIds.size === 0) return;
    if (!window.confirm(`Xóa vĩnh viễn ${selectedIds.size} mục đã chọn?`)) return;
    await repository.batchDelete(Array.from(selectedIds));
    setSelectedIds(new Set());
    setIsSelectMode(false);
    showToast('Đã xóa các mục đã chọn');
    await loadMedia();
  };

  // Batch Favorite
  const handleBatchFavorite = async () => {
    for (const id of selectedIds) {
      await repository.updateMeta(id, { isFavorite: true });
    }
    showToast(`Đã thêm ${selectedIds.size} mục vào Mục yêu thích`);
    setSelectedIds(new Set());
    setIsSelectMode(false);
    await loadMedia();
  };

  // Move items to album
  const handleMoveToAlbum = async () => {
    if (!targetMoveAlbum.trim()) return;
    for (const id of selectedIds) {
      await repository.updateMeta(id, { album: targetMoveAlbum.trim() });
    }
    showToast(`Đã chuyển ${selectedIds.size} ảnh vào album "${targetMoveAlbum}"`);
    setSelectedIds(new Set());
    setIsSelectMode(false);
    setIsMoveAlbumOpen(false);
    setTargetMoveAlbum('');
    await loadMedia();
  };

  // Export / Download
  const handleExportItem = async (item: VaultItem) => {
    try {
      const data = await repository.readBytes(item.id);
      const mime = item.kind === 'video' ? 'video/mp4' : 'image/png';
      const blob = new Blob([data.bytes], { type: mime });
      const url = URL.createObjectURL(blob);
      const a = document.createElement('a');
      a.href = url;
      a.download = data.name || `vault-media-${item.id.slice(0, 6)}.png`;
      document.body.appendChild(a);
      a.click();
      document.body.removeChild(a);
      URL.revokeObjectURL(url);
      showToast('Đã xuất bản sao giải mã về thiết bị');
    } catch {
      showToast('Lỗi khi xuất tệp');
    }
  };

  // Batch Export
  const handleBatchExport = async () => {
    for (const id of selectedIds) {
      const it = items.find((i) => i.id === id);
      if (it) await handleExportItem(it);
    }
    setSelectedIds(new Set());
    setIsSelectMode(false);
  };

  // Distinct albums list
  const albumList = useMemo(() => {
    const albumMap = new Map<string, number>();
    // Default categories
    albumMap.set('Máy ảnh', 0);
    albumMap.set('Kho ảnh riêng tư', 0);
    albumMap.set('Du lịch', 0);
    albumMap.set('Gia đình', 0);
    albumMap.set('Tài chính', 0);

    items.forEach((item) => {
      const alb = item.album || 'Kho ảnh riêng tư';
      albumMap.set(alb, (albumMap.get(alb) || 0) + 1);
    });

    return Array.from(albumMap.entries()).map(([name, count]) => ({
      name,
      count,
    }));
  }, [items]);

  // Filtered items based on activeTab, selectedAlbum, and searchQuery
  const filteredItems = useMemo(() => {
    let result = items;

    if (searchQuery.trim()) {
      const q = searchQuery.toLowerCase();
      result = result.filter(
        (i) => (i.name && i.name.toLowerCase().includes(q)) || (i.album && i.album.toLowerCase().includes(q))
      );
    }

    if (activeTab === 'videos') {
      result = result.filter((i) => i.kind === 'video');
    } else if (activeTab === 'favorites') {
      result = result.filter((i) => !!i.isFavorite);
    } else if (activeTab === 'albums' && selectedAlbum) {
      result = result.filter((i) => (i.album || 'Kho ảnh riêng tư') === selectedAlbum);
    }

    return result;
  }, [items, activeTab, selectedAlbum, searchQuery]);

  // Toggle selection
  const toggleSelect = (id: string, e: React.MouseEvent) => {
    e.stopPropagation();
    const next = new Set(selectedIds);
    if (next.has(id)) next.delete(id);
    else next.add(id);
    setSelectedIds(next);
  };

  const selectAll = () => {
    if (selectedIds.size === filteredItems.length) {
      setSelectedIds(new Set());
    } else {
      setSelectedIds(new Set(filteredItems.map((i) => i.id)));
    }
  };

  return (
    <div className="flex flex-col h-full bg-[#0d1314] text-zinc-100 select-none overflow-hidden relative font-sans">
      <input
        type="file"
        ref={fileInputRef}
        onChange={handleImportFile}
        accept="image/*,video/*"
        className="hidden"
      />

      {/* Top Gallery Header (Samsung OneUI Style) */}
      <header className="px-4 py-3 bg-[#131b1d] border-b border-zinc-800 shrink-0 flex items-center justify-between shadow-xs">
        <div className="flex items-center gap-2.5">
          {selectedAlbum && activeTab === 'albums' ? (
            <button
              onClick={() => setSelectedAlbum(null)}
              className="p-1 rounded-lg text-zinc-400 hover:text-white hover:bg-zinc-800 transition-colors"
            >
              <ChevronLeft className="w-5 h-5" />
            </button>
          ) : (
            <div className="w-7 h-7 rounded-lg bg-teal-500/20 text-teal-400 flex items-center justify-center">
              <ImageIcon className="w-4 h-4" />
            </div>
          )}
          <div>
            <h2 className="text-sm font-bold tracking-tight text-white flex items-center gap-2">
              <span>{selectedAlbum || 'Bộ sưu tập'}</span>
              <span className="text-[11px] font-mono font-normal text-zinc-400">
                ({filteredItems.length})
              </span>
            </h2>
            <p className="text-[10px] text-teal-400/90 font-mono">
              AES-256 Encrypted Vault
            </p>
          </div>
        </div>

        {/* Action icons */}
        <div className="flex items-center gap-1.5">
          <button
            onClick={() => setIsSearchOpen(!isSearchOpen)}
            className={`p-2 rounded-xl transition-colors ${
              isSearchOpen ? 'bg-zinc-800 text-teal-400' : 'text-zinc-400 hover:text-white hover:bg-zinc-800/60'
            }`}
            title="Tìm kiếm"
          >
            <Search className="w-4 h-4" />
          </button>

          <button
            onClick={startCamera}
            className="p-2 rounded-xl text-zinc-400 hover:text-white hover:bg-zinc-800/60 transition-colors"
            title="Chụp ảnh bảo mật"
          >
            <Camera className="w-4 h-4" />
          </button>

          <button
            onClick={() => fileInputRef.current?.click()}
            className="p-2 rounded-xl text-zinc-400 hover:text-white hover:bg-zinc-800/60 transition-colors"
            title="Nhập ảnh vào Vault"
          >
            <Plus className="w-4 h-4" />
          </button>

          <button
            onClick={() => {
              setIsSelectMode(!isSelectMode);
              setSelectedIds(new Set());
            }}
            className={`px-2.5 py-1.5 rounded-xl text-xs font-semibold transition-colors ${
              isSelectMode
                ? 'bg-teal-500 text-zinc-950 shadow-xs'
                : 'text-zinc-400 hover:text-white hover:bg-zinc-800/60'
            }`}
          >
            {isSelectMode ? 'Xong' : 'Chọn'}
          </button>
        </div>
      </header>

      {/* Search Bar Collapsible */}
      {isSearchOpen && (
        <div className="px-4 py-2 bg-[#172022] border-b border-zinc-800 shrink-0 flex items-center gap-2">
          <Search className="w-4 h-4 text-zinc-400 shrink-0" />
          <input
            type="text"
            value={searchQuery}
            onChange={(e) => setSearchQuery(e.target.value)}
            placeholder="Tìm theo tên ảnh hoặc tên album..."
            className="flex-1 bg-transparent text-xs text-white placeholder-zinc-500 focus:outline-none"
            autoFocus
          />
          {searchQuery && (
            <button onClick={() => setSearchQuery('')} className="text-zinc-400 hover:text-white">
              <X className="w-3.5 h-3.5" />
            </button>
          )}
        </div>
      )}

      {/* Segmented Filter Control (No pills, zero-pill discipline) */}
      <div className="px-3 py-2 bg-[#101718] border-b border-zinc-800/80 shrink-0">
        <div className="grid grid-cols-4 gap-1 p-1 bg-zinc-900/90 rounded-xl">
          <button
            onClick={() => {
              setActiveTab('pictures');
              setSelectedAlbum(null);
            }}
            className={`py-1.5 rounded-lg text-xs font-semibold transition-colors ${
              activeTab === 'pictures'
                ? 'bg-[#1b2628] text-teal-300 shadow-xs'
                : 'text-zinc-400 hover:text-zinc-200'
            }`}
          >
            Ảnh
          </button>
          <button
            onClick={() => {
              setActiveTab('albums');
              setSelectedAlbum(null);
            }}
            className={`py-1.5 rounded-lg text-xs font-semibold transition-colors ${
              activeTab === 'albums'
                ? 'bg-[#1b2628] text-teal-300 shadow-xs'
                : 'text-zinc-400 hover:text-zinc-200'
            }`}
          >
            Album
          </button>
          <button
            onClick={() => {
              setActiveTab('videos');
              setSelectedAlbum(null);
            }}
            className={`py-1.5 rounded-lg text-xs font-semibold transition-colors ${
              activeTab === 'videos'
                ? 'bg-[#1b2628] text-teal-300 shadow-xs'
                : 'text-zinc-400 hover:text-zinc-200'
            }`}
          >
            Video
          </button>
          <button
            onClick={() => {
              setActiveTab('favorites');
              setSelectedAlbum(null);
            }}
            className={`py-1.5 rounded-lg text-xs font-semibold transition-colors flex items-center justify-center gap-1 ${
              activeTab === 'favorites'
                ? 'bg-[#1b2628] text-rose-400 shadow-xs'
                : 'text-zinc-400 hover:text-zinc-200'
            }`}
          >
            <Heart className="w-3 h-3 fill-current text-rose-500" />
            <span>Yêu thích</span>
          </button>
        </div>
      </div>

      {/* Main Content Area */}
      <div className="flex-1 overflow-y-auto p-3 space-y-4">
        {/* Album Mode: If tab is 'albums' and no album is selected, show Album Grid */}
        {activeTab === 'albums' && !selectedAlbum ? (
          <div className="space-y-3">
            <div className="flex items-center justify-between px-1">
              <span className="text-xs font-semibold uppercase tracking-wider text-zinc-400">
                Các Album Bảo mật
              </span>
              <button
                onClick={() => setIsCreateAlbumOpen(true)}
                className="text-xs text-teal-400 hover:underline flex items-center gap-1"
              >
                <FolderPlus className="w-3.5 h-3.5" />
                <span>+ Tạo Album</span>
              </button>
            </div>

            <div className="grid grid-cols-2 gap-3">
              {albumList.map((alb) => (
                <div
                  key={alb.name}
                  onClick={() => setSelectedAlbum(alb.name)}
                  className="p-3.5 rounded-2xl bg-[#141d1f] border border-zinc-800/80 hover:border-zinc-700 cursor-pointer transition-all active:scale-[0.98] group flex flex-col justify-between aspect-4/3 shadow-xs"
                >
                  <div className="flex items-start justify-between">
                    <div className="w-9 h-9 rounded-xl bg-teal-500/10 text-teal-400 flex items-center justify-center group-hover:bg-teal-500/20 transition-colors">
                      <Folder className="w-5 h-5" />
                    </div>
                    <span className="text-xs font-mono text-zinc-500">{alb.count} mục</span>
                  </div>

                  <div>
                    <h4 className="text-xs font-bold text-white group-hover:text-teal-300 transition-colors truncate">
                      {alb.name}
                    </h4>
                    <p className="text-[10px] text-zinc-500">Mã hóa riêng tư</p>
                  </div>
                </div>
              ))}
            </div>
          </div>
        ) : filteredItems.length === 0 ? (
          /* Empty State */
          <div className="flex flex-col items-center justify-center py-20 text-center space-y-3">
            <div className="w-14 h-14 rounded-2xl bg-zinc-900 border border-zinc-800 flex items-center justify-center text-zinc-500">
              <ImageIcon className="w-7 h-7" />
            </div>
            <div>
              <p className="text-sm font-semibold text-zinc-300">Không có ảnh hoặc video nào</p>
              <p className="text-xs text-zinc-500 mt-1 max-w-xs">
                Nhập ảnh từ máy tính hoặc bấm "Nạp ảnh mẫu" để xem kho ảnh mẫu được mã hóa.
              </p>
            </div>
            <div className="flex items-center gap-2 pt-2">
              <button
                onClick={() => seedSampleVaultMedia(repository).then(loadMedia)}
                className="flex items-center gap-1.5 px-3 py-1.5 rounded-xl bg-teal-500/20 text-teal-300 border border-teal-500/30 text-xs font-semibold hover:bg-teal-500/30 transition-colors"
              >
                <Sparkles className="w-3.5 h-3.5" />
                <span>Nạp ảnh mẫu chất lượng cao</span>
              </button>
              <button
                onClick={() => fileInputRef.current?.click()}
                className="flex items-center gap-1.5 px-3 py-1.5 rounded-xl bg-zinc-800 text-zinc-200 text-xs font-semibold hover:bg-zinc-700 transition-colors"
              >
                <Plus className="w-3.5 h-3.5" />
                <span>Nhập ảnh</span>
              </button>
            </div>
          </div>
        ) : (
          /* Photos / Videos Grid (Responsive 3-columns) */
          <div className="space-y-4">
            {isSelectMode && (
              <div className="flex items-center justify-between px-1 text-xs text-zinc-400">
                <button
                  onClick={selectAll}
                  className="flex items-center gap-1 text-teal-400 hover:underline font-medium"
                >
                  {selectedIds.size === filteredItems.length ? <CheckSquare className="w-3.5 h-3.5" /> : <Square className="w-3.5 h-3.5" />}
                  <span>{selectedIds.size === filteredItems.length ? 'Bỏ chọn tất cả' : 'Chọn tất cả'}</span>
                </button>
                <span>Đã chọn: {selectedIds.size}</span>
              </div>
            )}

            <div className="grid grid-cols-3 gap-2">
              {filteredItems.map((item, idx) => {
                const isSelected = selectedIds.has(item.id);
                return (
                  <div
                    key={item.id}
                    onClick={() => {
                      if (isSelectMode) {
                        const next = new Set(selectedIds);
                        if (next.has(item.id)) next.delete(item.id);
                        else next.add(item.id);
                        setSelectedIds(next);
                      } else {
                        setViewingIndex(idx);
                      }
                    }}
                    className={`relative aspect-square rounded-xl overflow-hidden bg-zinc-900 border cursor-pointer group transition-all ${
                      isSelected
                        ? 'border-teal-400 ring-2 ring-teal-400/50'
                        : 'border-zinc-800 hover:border-zinc-600'
                    }`}
                  >
                    {/* Media Thumbnail Rendering */}
                    <div className="w-full h-full flex flex-col items-center justify-center bg-gradient-to-br from-zinc-900 to-[#121a1b] text-zinc-400">
                      {item.kind === 'video' ? (
                        <div className="flex flex-col items-center justify-center">
                          <Play className="w-6 h-6 text-sky-400" />
                          <span className="text-[9px] font-mono mt-1 text-zinc-400">VIDEO</span>
                        </div>
                      ) : (
                        <div className="flex flex-col items-center justify-center p-2 text-center">
                          <ImageIcon className="w-6 h-6 text-teal-400/80 mb-1" />
                          <span className="text-[10px] font-medium text-zinc-300 truncate max-w-[85px]">
                            {item.name || 'Ảnh bảo mật'}
                          </span>
                        </div>
                      )}
                    </div>

                    {/* Overlay Badges */}
                    <div className="absolute top-1.5 right-1.5 flex items-center gap-1">
                      {item.isFavorite && (
                        <div className="p-1 rounded-full bg-black/60 backdrop-blur-xs text-rose-500">
                          <Heart className="w-3 h-3 fill-current" />
                        </div>
                      )}
                    </div>

                    {item.album && (
                      <div className="absolute bottom-1 left-1 px-1.5 py-0.5 rounded-md bg-black/70 backdrop-blur-xs text-[9px] text-zinc-300 font-mono truncate max-w-[80px]">
                        {item.album}
                      </div>
                    )}

                    {/* Select Checkbox */}
                    {isSelectMode && (
                      <div
                        onClick={(e) => toggleSelect(item.id, e)}
                        className="absolute top-1.5 left-1.5 z-10"
                      >
                        {isSelected ? (
                          <div className="w-5 h-5 rounded-md bg-teal-500 text-zinc-950 flex items-center justify-center">
                            <CheckSquare className="w-4 h-4" />
                          </div>
                        ) : (
                          <div className="w-5 h-5 rounded-md bg-black/60 border border-zinc-500" />
                        )}
                      </div>
                    )}
                  </div>
                );
              })}
            </div>
          </div>
        )}
      </div>

      {/* Batch Action Toolbar when in Selection Mode */}
      {isSelectMode && selectedIds.size > 0 && (
        <div className="p-3 bg-[#131b1d] border-t border-zinc-800 flex items-center justify-around shrink-0 animate-in slide-in-from-bottom">
          <button
            onClick={handleBatchFavorite}
            className="flex flex-col items-center gap-1 text-xs text-zinc-300 hover:text-white"
          >
            <Heart className="w-4 h-4 text-rose-400" />
            <span className="text-[10px]">Yêu thích</span>
          </button>
          <button
            onClick={() => setIsMoveAlbumOpen(true)}
            className="flex flex-col items-center gap-1 text-xs text-zinc-300 hover:text-white"
          >
            <Folder className="w-4 h-4 text-teal-400" />
            <span className="text-[10px]">Chuyển Album</span>
          </button>
          <button
            onClick={handleBatchExport}
            className="flex flex-col items-center gap-1 text-xs text-zinc-300 hover:text-white"
          >
            <Download className="w-4 h-4 text-sky-400" />
            <span className="text-[10px]">Xuất file</span>
          </button>
          <button
            onClick={handleBatchDelete}
            className="flex flex-col items-center gap-1 text-xs text-rose-400 hover:text-rose-300"
          >
            <Trash2 className="w-4 h-4" />
            <span className="text-[10px]">Xóa ({selectedIds.size})</span>
          </button>
        </div>
      )}

      {/* Lightbox / Full-screen Media Viewer */}
      {viewingIndex !== null && viewingIndex >= 0 && viewingIndex < filteredItems.length && (
        <div className="fixed inset-0 z-50 bg-black/95 flex flex-col justify-between select-none">
          {/* Lightbox Top Header */}
          <div className="px-4 py-3 bg-black/70 backdrop-blur-md flex items-center justify-between border-b border-zinc-800/80 z-20">
            <div className="flex items-center gap-3">
              <button
                onClick={() => setViewingIndex(null)}
                className="p-1 rounded-lg text-zinc-400 hover:text-white"
              >
                <X className="w-5 h-5" />
              </button>
              <div>
                <p className="text-xs font-bold text-white truncate max-w-[180px]">
                  {filteredItems[viewingIndex].name}
                </p>
                <p className="text-[10px] text-zinc-400 font-mono">
                  {viewingIndex + 1} / {filteredItems.length}
                </p>
              </div>
            </div>

            <div className="flex items-center gap-2">
              <button
                onClick={() => setZoomLevel((z) => (z < 3 ? z + 0.5 : 1))}
                className="p-1.5 rounded-lg text-zinc-400 hover:text-white hover:bg-zinc-800"
                title="Thu phóng"
              >
                {zoomLevel > 1 ? <ZoomOut className="w-4 h-4" /> : <ZoomIn className="w-4 h-4" />}
              </button>
              <button
                onClick={() => setIsSlideshowActive(!isSlideshowActive)}
                className={`p-1.5 rounded-lg transition-colors ${
                  isSlideshowActive ? 'bg-teal-500 text-zinc-950' : 'text-zinc-400 hover:text-white hover:bg-zinc-800'
                }`}
                title="Trình chiếu tự động"
              >
                <Play className="w-4 h-4" />
              </button>
              <button
                onClick={() => setShowInfoModal(true)}
                className="p-1.5 rounded-lg text-zinc-400 hover:text-white hover:bg-zinc-800"
                title="Thông tin chi tiết"
              >
                <Info className="w-4 h-4" />
              </button>
            </div>
          </div>

          {/* Lightbox Main Media View */}
          <div className="flex-1 relative flex items-center justify-center overflow-hidden p-4">
            {/* Prev button */}
            <button
              onClick={() =>
                setViewingIndex((prev) => (prev !== null && prev > 0 ? prev - 1 : filteredItems.length - 1))
              }
              className="absolute left-3 p-2.5 rounded-full bg-black/60 text-white hover:bg-black/80 z-10"
            >
              <ChevronLeft className="w-5 h-5" />
            </button>

            {/* Media Canvas/Image */}
            {viewingDecryptedUrl ? (
              filteredItems[viewingIndex].kind === 'video' ? (
                <video
                  src={viewingDecryptedUrl}
                  controls
                  autoPlay
                  className="max-h-[75vh] max-w-full rounded-xl shadow-2xl"
                />
              ) : (
                <img
                  src={viewingDecryptedUrl}
                  alt={filteredItems[viewingIndex].name}
                  style={{ transform: `scale(${zoomLevel})` }}
                  className="max-h-[75vh] max-w-full object-contain rounded-xl shadow-2xl transition-transform duration-200"
                />
              )
            ) : (
              <div className="flex flex-col items-center gap-2 text-zinc-500">
                <div className="w-8 h-8 border-2 border-teal-500 border-t-transparent rounded-full animate-spin" />
                <span className="text-xs">Đang giải mã bằng AES-GCM...</span>
              </div>
            )}

            {/* Next button */}
            <button
              onClick={() =>
                setViewingIndex((prev) => (prev !== null && prev < filteredItems.length - 1 ? prev + 1 : 0))
              }
              className="absolute right-3 p-2.5 rounded-full bg-black/60 text-white hover:bg-black/80 z-10"
            >
              <ChevronRight className="w-5 h-5" />
            </button>
          </div>

          {/* Lightbox Bottom Controls */}
          <div className="px-6 py-4 bg-black/70 backdrop-blur-md flex items-center justify-around border-t border-zinc-800/80 z-20">
            <button
              onClick={() => handleToggleFavorite(filteredItems[viewingIndex])}
              className="flex flex-col items-center gap-1 text-xs text-zinc-300 hover:text-white"
            >
              <Heart
                className={`w-5 h-5 ${
                  filteredItems[viewingIndex].isFavorite
                    ? 'fill-rose-500 text-rose-500'
                    : 'text-zinc-400'
                }`}
              />
              <span className="text-[10px]">
                {filteredItems[viewingIndex].isFavorite ? 'Đã thích' : 'Yêu thích'}
              </span>
            </button>

            <button
              onClick={() => handleExportItem(filteredItems[viewingIndex])}
              className="flex flex-col items-center gap-1 text-xs text-zinc-300 hover:text-white"
            >
              <Share2 className="w-5 h-5 text-teal-400" />
              <span className="text-[10px]">Xuất ra máy</span>
            </button>

            <button
              onClick={() => handleDeleteItem(filteredItems[viewingIndex])}
              className="flex flex-col items-center gap-1 text-xs text-rose-400 hover:text-rose-300"
            >
              <Trash2 className="w-5 h-5" />
              <span className="text-[10px]">Xóa</span>
            </button>
          </div>
        </div>
      )}

      {/* Info Modal */}
      {showInfoModal && viewingIndex !== null && (
        <div className="fixed inset-0 z-60 flex items-center justify-center bg-black/70 backdrop-blur-xs p-4">
          <div className="w-full max-w-sm bg-zinc-900 border border-zinc-800 rounded-3xl p-5 shadow-2xl space-y-4">
            <div className="flex items-center justify-between pb-2 border-b border-zinc-800">
              <h3 className="text-sm font-bold text-white flex items-center gap-2">
                <Info className="w-4 h-4 text-teal-400" />
                <span>Chi tiết tệp mã hóa</span>
              </h3>
              <button onClick={() => setShowInfoModal(false)} className="text-zinc-400 hover:text-white">
                <X className="w-4 h-4" />
              </button>
            </div>

            <div className="space-y-2 text-xs text-zinc-300 font-mono">
              <div className="flex justify-between">
                <span className="text-zinc-500">Tên:</span>
                <span className="text-white font-semibold truncate max-w-[180px]">
                  {filteredItems[viewingIndex].name}
                </span>
              </div>
              <div className="flex justify-between">
                <span className="text-zinc-500">Loại:</span>
                <span className="capitalize">{filteredItems[viewingIndex].kind}</span>
              </div>
              <div className="flex justify-between">
                <span className="text-zinc-500">Album:</span>
                <span>{filteredItems[viewingIndex].album || 'Kho ảnh riêng tư'}</span>
              </div>
              <div className="flex justify-between">
                <span className="text-zinc-500">Dung lượng:</span>
                <span>
                  {filteredItems[viewingIndex].size
                    ? `${(filteredItems[viewingIndex].size! / 1024).toFixed(1)} KB`
                    : 'Không xác định'}
                </span>
              </div>
              <div className="flex justify-between">
                <span className="text-zinc-500">Thuật toán:</span>
                <span className="text-teal-400 font-bold">AES-256-GCM (Hardware sealed)</span>
              </div>
              <div className="flex justify-between">
                <span className="text-zinc-500">Ngày tạo:</span>
                <span>{new Date(filteredItems[viewingIndex].createdAt).toLocaleString()}</span>
              </div>
            </div>

            <button
              onClick={() => setShowInfoModal(false)}
              className="w-full py-2.5 rounded-xl bg-zinc-800 hover:bg-zinc-700 text-white font-semibold text-xs"
            >
              Đóng
            </button>
          </div>
        </div>
      )}

      {/* Live Camera Viewfinder Modal */}
      {isCameraActive && (
        <div className="fixed inset-0 z-60 bg-black flex flex-col justify-between">
          <div className="p-4 flex items-center justify-between text-white bg-black/60 z-10">
            <span className="text-xs font-bold uppercase tracking-wider text-teal-400 flex items-center gap-1.5">
              <Camera className="w-4 h-4" />
              <span>Máy ảnh bảo mật (Trực tiếp vào Vault)</span>
            </span>
            <button onClick={stopCamera} className="p-1 rounded-full hover:bg-zinc-800">
              <X className="w-5 h-5" />
            </button>
          </div>

          <div className="flex-1 relative flex items-center justify-center overflow-hidden">
            <video ref={videoRef} playsInline autoPlay className="w-full h-full object-cover" />
          </div>

          <div className="p-6 bg-black/90 flex items-center justify-center gap-6">
            <button
              onClick={capturePhoto}
              className="w-18 h-18 rounded-full border-4 border-white flex items-center justify-center hover:bg-white/20 active:scale-95 transition-all"
            >
              <div className="w-14 h-14 rounded-full bg-teal-400" />
            </button>
          </div>
        </div>
      )}

      {/* Create Album Modal */}
      {isCreateAlbumOpen && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/70 backdrop-blur-xs p-4">
          <div className="w-full max-w-xs bg-zinc-900 border border-zinc-800 rounded-3xl p-5 shadow-2xl space-y-4">
            <h3 className="text-sm font-bold text-white">Tạo Album mới</h3>
            <input
              type="text"
              value={newAlbumName}
              onChange={(e) => setNewAlbumName(e.target.value)}
              placeholder="Nhập tên album..."
              className="w-full p-2.5 rounded-xl bg-zinc-800 border border-zinc-700 text-xs text-white focus:outline-none focus:ring-2 focus:ring-teal-500"
              autoFocus
            />
            <div className="flex justify-end gap-2 pt-2">
              <button
                onClick={() => setIsCreateAlbumOpen(false)}
                className="px-3.5 py-1.5 rounded-xl text-xs text-zinc-400 hover:bg-zinc-800"
              >
                Hủy
              </button>
              <button
                onClick={() => {
                  if (newAlbumName.trim()) {
                    setSelectedAlbum(newAlbumName.trim());
                    setIsCreateAlbumOpen(false);
                    setNewAlbumName('');
                    showToast(`Đã tạo album "${newAlbumName.trim()}"`);
                  }
                }}
                disabled={!newAlbumName.trim()}
                className="px-4 py-1.5 rounded-xl text-xs font-semibold bg-teal-500 text-zinc-950 disabled:opacity-40"
              >
                Tạo
              </button>
            </div>
          </div>
        </div>
      )}

      {/* Move to Album Modal */}
      {isMoveAlbumOpen && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/70 backdrop-blur-xs p-4">
          <div className="w-full max-w-xs bg-zinc-900 border border-zinc-800 rounded-3xl p-5 shadow-2xl space-y-4">
            <h3 className="text-sm font-bold text-white">Chuyển vào Album</h3>
            <div className="space-y-1 max-h-48 overflow-y-auto">
              {albumList.map((alb) => (
                <button
                  key={alb.name}
                  onClick={() => setTargetMoveAlbum(alb.name)}
                  className={`w-full p-2 rounded-xl text-left text-xs flex items-center justify-between transition-colors ${
                    targetMoveAlbum === alb.name ? 'bg-teal-500 text-zinc-950 font-bold' : 'text-zinc-300 hover:bg-zinc-800'
                  }`}
                >
                  <span>{alb.name}</span>
                  <span className="font-mono text-[10px] opacity-70">{alb.count}</span>
                </button>
              ))}
            </div>
            <input
              type="text"
              value={targetMoveAlbum}
              onChange={(e) => setTargetMoveAlbum(e.target.value)}
              placeholder="Hoặc nhập tên album mới..."
              className="w-full p-2 rounded-xl bg-zinc-800 border border-zinc-700 text-xs text-white"
            />
            <div className="flex justify-end gap-2 pt-2">
              <button
                onClick={() => setIsMoveAlbumOpen(false)}
                className="px-3.5 py-1.5 rounded-xl text-xs text-zinc-400 hover:bg-zinc-800"
              >
                Hủy
              </button>
              <button
                onClick={handleMoveToAlbum}
                disabled={!targetMoveAlbum.trim()}
                className="px-4 py-1.5 rounded-xl text-xs font-semibold bg-teal-500 text-zinc-950 disabled:opacity-40"
              >
                Chuyển
              </button>
            </div>
          </div>
        </div>
      )}

      {/* Toast Notification */}
      {notification && (
        <div className="absolute bottom-4 left-1/2 -translate-x-1/2 z-50 px-4 py-2 rounded-xl bg-teal-500 text-zinc-950 font-semibold text-xs shadow-2xl animate-in fade-in slide-in-from-bottom-2">
          {notification}
        </div>
      )}
    </div>
  );
};
