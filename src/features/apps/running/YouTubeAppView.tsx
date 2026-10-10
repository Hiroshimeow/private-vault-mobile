import React, { useState } from 'react';
import {
  ChevronLeft,
  Search,
  Home,
  Compass,
  PlaySquare,
  Clock,
  ThumbsUp,
  Share2,
  Download,
  CheckCircle2,
  ExternalLink,
  Shield,
  User,
} from 'lucide-react';
import { LocalVaultRepository } from '../../vault/vaultRepository';

interface YouTubeAppViewProps {
  appName: string;
  onBack: () => void;
  repository?: LocalVaultRepository;
}

interface VideoItem {
  id: string;
  title: string;
  channel: string;
  views: string;
  timeAgo: string;
  duration: string;
  youtubeId: string;
  channelAvatar: string;
}

const SAMPLE_VIDEOS: VideoItem[] = [
  {
    id: '1',
    title: 'Samsung Galaxy S24 Ultra - Đánh giá chi tiết sau 6 tháng sử dụng Thư mục bảo mật',
    channel: 'Vật Vờ Studio',
    views: '452K lượt xem',
    timeAgo: '2 tuần trước',
    duration: '14:28',
    youtubeId: 'M7lc1UVf-VE',
    channelAvatar: 'https://images.unsplash.com/photo-1535713875002-d1d0cf377fde?w=100&auto=format&fit=crop&q=80',
  },
  {
    id: '2',
    title: 'Hướng dẫn cài đặt YouTube ReVanced Morphe không quảng cáo, chạy nền an toàn',
    channel: 'Tech Tips VN',
    views: '1.2M lượt xem',
    timeAgo: '1 tháng trước',
    duration: '08:45',
    youtubeId: 'dQw4w9WgXcQ',
    channelAvatar: 'https://images.unsplash.com/photo-1570295999919-56ceb5ecca61?w=100&auto=format&fit=crop&q=80',
  },
  {
    id: '3',
    title: 'Top 10 tính năng ẩn trên One UI 6.1 bạn nhất định phải bật ngay',
    channel: 'Schannel Tech',
    views: '280K lượt xem',
    timeAgo: '3 ngày trước',
    duration: '11:15',
    youtubeId: 'L_LUpnjgPso',
    channelAvatar: 'https://images.unsplash.com/photo-1580489944761-15a19d654956?w=100&auto=format&fit=crop&q=80',
  },
  {
    id: '4',
    title: 'Bảo mật Android Work Profile và Knox Vault hoạt động như thế nào?',
    channel: 'CyberSec Lab',
    views: '98K lượt xem',
    timeAgo: '5 ngày trước',
    duration: '19:30',
    youtubeId: 'jNQXAC9IVRw',
    channelAvatar: 'https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?w=100&auto=format&fit=crop&q=80',
  },
];

export const YouTubeAppView: React.FC<YouTubeAppViewProps> = ({
  appName,
  onBack,
  repository,
}) => {
  const [activeVideo, setActiveVideo] = useState<VideoItem | null>(null);
  const [searchQuery, setSearchQuery] = useState('');
  const [isSearching, setIsSearching] = useState(false);
  const [activeTab, setActiveTab] = useState<'home' | 'shorts' | 'subscriptions' | 'library'>('home');
  const [isLiked, setIsLiked] = useState(false);
  const [isSubscribed, setIsSubscribed] = useState(false);
  const [isSavedToVault, setIsSavedToVault] = useState(false);
  const [toastMsg, setToastMsg] = useState<string | null>(null);

  const showToast = (msg: string) => {
    setToastMsg(msg);
    setTimeout(() => setToastMsg(null), 3000);
  };

  const handleSaveToVault = async (video: VideoItem) => {
    if (!repository) {
      showToast('Đã lưu thông tin video vào thư viện bí mật');
      setIsSavedToVault(true);
      return;
    }

    try {
      const info = `TIÊU ĐỀ: ${video.title}\nKÊNH: ${video.channel}\nYOUTUBE ID: ${video.youtubeId}\nTHỜI GIAN LƯU: ${new Date().toISOString()}`;
      const encoder = new TextEncoder();
      await repository.addBytes(encoder.encode(info), {
        kind: 'document',
        name: `YouTube_${video.youtubeId}.txt`,
        album: 'Video Vault',
      });
      setIsSavedToVault(true);
      showToast('Đã mã hóa và lưu bookmark video vào Vault Gallery!');
    } catch {
      showToast('Lỗi khi lưu vào Vault');
    }
  };

  const filteredVideos = SAMPLE_VIDEOS.filter(
    (v) =>
      v.title.toLowerCase().includes(searchQuery.toLowerCase()) ||
      v.channel.toLowerCase().includes(searchQuery.toLowerCase())
  );

  return (
    <div className="flex flex-col h-full bg-[#0f0f0f] text-white select-none overflow-hidden font-sans">
      {/* Toast */}
      {toastMsg && (
        <div className="absolute top-14 left-1/2 -translate-x-1/2 z-50 bg-red-600 text-white px-4 py-2 rounded-full text-xs font-semibold shadow-xl border border-white/20 animate-fade-in flex items-center gap-1.5">
          <CheckCircle2 className="w-4 h-4" />
          <span>{toastMsg}</span>
        </div>
      )}

      {/* App Top Bar */}
      <div className="px-3 py-2.5 bg-[#0f0f0f] border-b border-zinc-800 flex items-center justify-between shrink-0">
        <div className="flex items-center gap-2">
          <button
            onClick={() => {
              if (activeVideo) setActiveVideo(null);
              else onBack();
            }}
            className="p-1 rounded-full hover:bg-white/10 text-zinc-300"
          >
            <ChevronLeft className="w-5 h-5" />
          </button>
          <div className="flex items-center gap-1.5">
            <div className="w-6 h-5 rounded-md bg-red-600 flex items-center justify-center">
              <div className="w-0 h-0 border-y-3 border-y-transparent border-l-5 border-l-white ml-0.5" />
            </div>
            <span className="text-sm font-bold tracking-tighter">{appName.includes('Morphe') || appName.includes('ReVanced') ? 'YouTube Morphe' : 'YouTube'}</span>
            <span className="text-[9px] px-1.5 py-0.2 rounded-sm bg-red-500/20 text-red-400 font-mono">
              Sandbox
            </span>
          </div>
        </div>

        <div className="flex items-center gap-1">
          <button
            onClick={() => setIsSearching(!isSearching)}
            className="p-1.5 rounded-full hover:bg-white/10 text-zinc-300"
          >
            <Search className="w-4 h-4" />
          </button>
          <button
            onClick={() => window.open('https://youtube.com', '_blank')}
            title="Mở trên YouTube Web"
            className="p-1.5 rounded-full hover:bg-white/10 text-zinc-300"
          >
            <ExternalLink className="w-4 h-4" />
          </button>
          <div className="w-7 h-7 rounded-full bg-zinc-700 flex items-center justify-center text-xs font-bold ml-1">
            <User className="w-3.5 h-3.5 text-zinc-300" />
          </div>
        </div>
      </div>

      {/* Search Input if toggled */}
      {isSearching && (
        <div className="p-2 bg-zinc-900 border-b border-zinc-800 flex items-center gap-2">
          <div className="flex-1 flex items-center gap-2 bg-zinc-800 px-3 py-1.5 rounded-full">
            <Search className="w-4 h-4 text-zinc-400" />
            <input
              type="text"
              value={searchQuery}
              onChange={(e) => setSearchQuery(e.target.value)}
              placeholder="Tìm kiếm video trên YouTube..."
              className="bg-transparent text-xs text-white outline-hidden w-full placeholder-zinc-500"
              autoFocus
            />
          </div>
          <button
            onClick={() => {
              setSearchQuery('');
              setIsSearching(false);
            }}
            className="text-xs text-zinc-400 px-2 py-1"
          >
            Hủy
          </button>
        </div>
      )}

      {/* Active Video Player View */}
      {activeVideo ? (
        <div className="flex-1 overflow-y-auto flex flex-col bg-[#0f0f0f]">
          {/* Responsive Embedded Iframe Player */}
          <div className="w-full aspect-video bg-black relative shrink-0">
            <iframe
              src={`https://www.youtube-nocookie.com/embed/${activeVideo.youtubeId}?autoplay=1&rel=0`}
              title={activeVideo.title}
              className="w-full h-full border-0"
              allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture"
              allowFullScreen
            />
          </div>

          {/* Video Metadata */}
          <div className="p-3 space-y-3">
            <h2 className="text-sm font-bold text-white leading-snug">
              {activeVideo.title}
            </h2>
            <div className="flex items-center gap-2 text-xs text-zinc-400">
              <span>{activeVideo.views}</span>
              <span>•</span>
              <span>{activeVideo.timeAgo}</span>
              <span className="px-1.5 py-0.5 rounded-sm bg-zinc-800 text-[10px] text-teal-400 font-mono">
                No Ads Sandbox
              </span>
            </div>

            {/* Channel info & Subscribe */}
            <div className="flex items-center justify-between pt-1 pb-2 border-b border-zinc-800">
              <div className="flex items-center gap-2.5">
                <img
                  src={activeVideo.channelAvatar}
                  alt={activeVideo.channel}
                  className="w-8 h-8 rounded-full object-cover"
                />
                <div>
                  <h4 className="text-xs font-bold text-white">{activeVideo.channel}</h4>
                  <p className="text-[10px] text-zinc-400">845K người đăng ký</p>
                </div>
              </div>

              <button
                onClick={() => {
                  setIsSubscribed(!isSubscribed);
                  showToast(isSubscribed ? 'Đã hủy đăng ký' : 'Đã đăng ký kênh');
                }}
                className={`px-3 py-1.5 rounded-full text-xs font-bold transition-all ${
                  isSubscribed
                    ? 'bg-zinc-800 text-zinc-300'
                    : 'bg-white text-black hover:bg-zinc-200'
                }`}
              >
                {isSubscribed ? 'Đã đăng ký' : 'Đăng ký'}
              </button>
            </div>

            {/* Action Bar (Like, Share, Download to Vault) */}
            <div className="flex items-center gap-2 overflow-x-auto py-1 scrollbar-none">
              <button
                onClick={() => setIsLiked(!isLiked)}
                className={`flex items-center gap-1.5 px-3 py-1.5 rounded-full text-xs font-semibold shrink-0 transition-colors ${
                  isLiked ? 'bg-white text-black' : 'bg-zinc-800 text-zinc-200'
                }`}
              >
                <ThumbsUp className="w-3.5 h-3.5 fill-current" />
                <span>Thích</span>
              </button>

              <button
                onClick={() => {
                  if (navigator.clipboard) {
                    navigator.clipboard.writeText(`https://youtu.be/${activeVideo.youtubeId}`);
                    showToast('Đã sao chép liên kết video');
                  }
                }}
                className="flex items-center gap-1.5 px-3 py-1.5 rounded-full bg-zinc-800 text-zinc-200 text-xs font-semibold shrink-0"
              >
                <Share2 className="w-3.5 h-3.5" />
                <span>Chia sẻ</span>
              </button>

              <button
                onClick={() => handleSaveToVault(activeVideo)}
                className={`flex items-center gap-1.5 px-3 py-1.5 rounded-full text-xs font-semibold shrink-0 transition-colors ${
                  isSavedToVault
                    ? 'bg-teal-500 text-zinc-950'
                    : 'bg-zinc-800 text-zinc-200 hover:bg-zinc-700'
                }`}
              >
                <Download className="w-3.5 h-3.5" />
                <span>{isSavedToVault ? 'Đã lưu Vault' : 'Tải vào Vault'}</span>
              </button>

              <div className="flex items-center gap-1 px-3 py-1.5 rounded-full bg-zinc-800/80 text-teal-400 text-xs font-mono shrink-0">
                <Shield className="w-3 h-3" />
                <span>ReVanced Patch Active</span>
              </div>
            </div>

            {/* Up Next List */}
            <div className="pt-3 space-y-3">
              <h3 className="text-xs font-bold uppercase tracking-wider text-zinc-400">
                Video liên quan
              </h3>
              {SAMPLE_VIDEOS.filter((v) => v.id !== activeVideo.id).map((video) => (
                <div
                  key={video.id}
                  onClick={() => {
                    setActiveVideo(video);
                    setIsLiked(false);
                    setIsSavedToVault(false);
                  }}
                  className="flex gap-2.5 cursor-pointer group"
                >
                  <div className="w-32 aspect-video bg-zinc-800 rounded-lg overflow-hidden relative shrink-0">
                    <img
                      src={`https://img.youtube.com/vi/${video.youtubeId}/mqdefault.jpg`}
                      alt={video.title}
                      className="w-full h-full object-cover group-hover:scale-105 transition-transform"
                    />
                    <div className="absolute bottom-1 right-1 px-1 rounded-sm bg-black/80 text-[9px] font-mono">
                      {video.duration}
                    </div>
                  </div>
                  <div className="flex-1 min-w-0">
                    <h4 className="text-xs font-semibold text-white leading-tight line-clamp-2 group-hover:text-red-400">
                      {video.title}
                    </h4>
                    <p className="text-[10px] text-zinc-400 mt-1">{video.channel}</p>
                    <p className="text-[10px] text-zinc-500">
                      {video.views} • {video.timeAgo}
                    </p>
                  </div>
                </div>
              ))}
            </div>
          </div>
        </div>
      ) : (
        /* Video Feed (YouTube Home / Trending) */
        <div className="flex-1 overflow-y-auto space-y-4 pb-14">
          {/* Quick Categories Bar */}
          <div className="flex items-center gap-2 px-3 pt-2 overflow-x-auto scrollbar-none">
            {['Tất cả', 'Công nghệ', 'Bảo mật', 'Samsung', 'Mẹo vặt', 'Nhạc EDM', 'Trực tiếp'].map(
              (cat, i) => (
                <button
                  key={cat}
                  className={`px-3 py-1 rounded-lg text-xs font-semibold whitespace-nowrap ${
                    i === 0
                      ? 'bg-white text-black'
                      : 'bg-zinc-800 text-zinc-300 hover:bg-zinc-700'
                  }`}
                >
                  {cat}
                </button>
              )
            )}
          </div>

          {/* Videos Grid */}
          <div className="space-y-4">
            {filteredVideos.map((video) => (
              <div
                key={video.id}
                onClick={() => setActiveVideo(video)}
                className="cursor-pointer group"
              >
                {/* Thumbnail */}
                <div className="w-full aspect-video bg-zinc-800 relative overflow-hidden">
                  <img
                    src={`https://img.youtube.com/vi/${video.youtubeId}/hqdefault.jpg`}
                    alt={video.title}
                    className="w-full h-full object-cover group-hover:scale-102 transition-transform duration-200"
                  />
                  <div className="absolute bottom-2 right-2 px-1.5 py-0.5 rounded-sm bg-black/85 text-[10px] font-mono text-zinc-200">
                    {video.duration}
                  </div>
                </div>

                {/* Metadata */}
                <div className="p-3 flex gap-3">
                  <img
                    src={video.channelAvatar}
                    alt={video.channel}
                    className="w-9 h-9 rounded-full object-cover shrink-0 mt-0.5"
                  />
                  <div className="flex-1 min-w-0">
                    <h3 className="text-xs font-bold text-white leading-snug line-clamp-2 group-hover:text-red-400">
                      {video.title}
                    </h3>
                    <p className="text-[11px] text-zinc-400 mt-1">
                      {video.channel} • {video.views} • {video.timeAgo}
                    </p>
                  </div>
                </div>
              </div>
            ))}
          </div>
        </div>
      )}

      {/* Bottom Tabs */}
      <div className="h-12 bg-[#0f0f0f] border-t border-zinc-800 flex items-center justify-around shrink-0 text-zinc-400">
        <button
          onClick={() => {
            setActiveTab('home');
            setActiveVideo(null);
          }}
          className={`flex flex-col items-center gap-0.5 ${
            activeTab === 'home' ? 'text-white font-bold' : 'hover:text-zinc-200'
          }`}
        >
          <Home className="w-4 h-4" />
          <span className="text-[9px]">Trang chủ</span>
        </button>
        <button
          onClick={() => setActiveTab('shorts')}
          className={`flex flex-col items-center gap-0.5 ${
            activeTab === 'shorts' ? 'text-white font-bold' : 'hover:text-zinc-200'
          }`}
        >
          <PlaySquare className="w-4 h-4" />
          <span className="text-[9px]">Shorts</span>
        </button>
        <button
          onClick={() => setActiveTab('subscriptions')}
          className={`flex flex-col items-center gap-0.5 ${
            activeTab === 'subscriptions' ? 'text-white font-bold' : 'hover:text-zinc-200'
          }`}
        >
          <Compass className="w-4 h-4" />
          <span className="text-[9px]">Đăng ký</span>
        </button>
        <button
          onClick={() => setActiveTab('library')}
          className={`flex flex-col items-center gap-0.5 ${
            activeTab === 'library' ? 'text-white font-bold' : 'hover:text-zinc-200'
          }`}
        >
          <Clock className="w-4 h-4" />
          <span className="text-[9px]">Bạn</span>
        </button>
      </div>
    </div>
  );
};
