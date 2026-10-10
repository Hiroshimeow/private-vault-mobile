import React, { useState } from 'react';
import {
  ChevronLeft,
  Heart,
  MessageCircle,
  Share2,
  ExternalLink,
  MoreHorizontal,
} from 'lucide-react';

interface SocialAppViewProps {
  appName: string;
  packageName: string;
  onBack: () => void;
}

export const SocialAppView: React.FC<SocialAppViewProps> = ({
  appName,
  packageName,
  onBack,
}) => {
  const [posts, setPosts] = useState([
    {
      id: 'p1',
      author: 'Tech Innovator',
      time: '2 giờ trước',
      content: 'Bảo mật dữ liệu trên điện thoại là ưu tiên hàng đầu. Tính năng Thư mục Bảo mật giúp cách ly hoàn toàn tài khoản phụ và ứng dụng.',
      likes: 38,
      isLiked: false,
      comments: 6,
    },
    {
      id: 'p2',
      author: 'CyberSecurity Vietnam',
      time: '5 giờ trước',
      content: 'Mẹo an toàn: Sử dụng hồ sơ người dùng độc lập (Multi-User Android Profile) để ngăn ngừa các ứng dụng đọc lén dữ liệu chéo.',
      likes: 124,
      isLiked: true,
      comments: 18,
    },
  ]);

  const [newPostText, setNewPostText] = useState('');

  const handleLike = (id: string) => {
    setPosts((prev) =>
      prev.map((p) =>
        p.id === id
          ? {
              ...p,
              isLiked: !p.isLiked,
              likes: p.isLiked ? p.likes - 1 : p.likes + 1,
            }
          : p
      )
    );
  };

  const handleCreatePost = (e: React.FormEvent) => {
    e.preventDefault();
    if (!newPostText.trim()) return;

    const newP = {
      id: `p-${Date.now()}`,
      author: 'Tài khoản nhân bản (Bạn)',
      time: 'Vừa xong',
      content: newPostText.trim(),
      likes: 1,
      isLiked: true,
      comments: 0,
    };
    setPosts([newP, ...posts]);
    setNewPostText('');
  };

  const getWebUrl = () => {
    if (packageName.includes('facebook')) return 'https://m.facebook.com';
    if (packageName.includes('twitter')) return 'https://x.com';
    if (packageName.includes('tiktok')) return 'https://www.tiktok.com';
    return null;
  };

  const webUrl = getWebUrl();

  return (
    <div className="flex flex-col h-full bg-[#f0f2f5] dark:bg-[#111417] text-zinc-900 dark:text-zinc-100 select-none overflow-hidden font-sans">
      {/* Header */}
      <div className="bg-[#1877f2] text-white px-3.5 py-3 flex items-center justify-between shadow-md shrink-0">
        <div className="flex items-center gap-2.5">
          <button onClick={onBack} className="p-1 rounded-full hover:bg-white/20">
            <ChevronLeft className="w-5 h-5" />
          </button>
          <div>
            <div className="flex items-center gap-1.5">
              <h3 className="text-sm font-bold">{appName || 'Facebook'}</h3>
              <span className="text-[10px] px-1.5 py-0.2 rounded bg-white/25 font-mono">
                Clone
              </span>
            </div>
            <p className="text-[10px] text-white/80">Không gian tách biệt</p>
          </div>
        </div>

        <div className="flex items-center gap-2">
          {webUrl && (
            <a
              href={webUrl}
              target="_blank"
              rel="noopener noreferrer"
              className="text-[11px] bg-white/20 hover:bg-white/30 text-white px-2.5 py-1 rounded-lg flex items-center gap-1"
            >
              <span>Mở Web</span>
              <ExternalLink className="w-3 h-3" />
            </a>
          )}
        </div>
      </div>

      {/* Feed */}
      <div className="flex-1 overflow-y-auto p-3 space-y-3">
        {/* Create post box */}
        <div className="p-3 rounded-2xl bg-white dark:bg-[#1a1f24] border border-zinc-200/80 dark:border-zinc-800 shadow-xs space-y-2">
          <textarea
            value={newPostText}
            onChange={(e) => setNewPostText(e.target.value)}
            placeholder="Bạn đang nghĩ gì trong tài khoản bảo mật?"
            rows={2}
            className="w-full text-xs bg-transparent text-zinc-900 dark:text-zinc-100 placeholder-zinc-400 focus:outline-none resize-none"
          />
          <div className="flex justify-end pt-1 border-t border-zinc-100 dark:border-zinc-800">
            <button
              onClick={handleCreatePost}
              disabled={!newPostText.trim()}
              className="px-3.5 py-1.5 rounded-xl bg-[#1877f2] text-white text-xs font-semibold disabled:opacity-40 hover:opacity-90 transition-opacity"
            >
              Đăng bài
            </button>
          </div>
        </div>

        {/* Posts list */}
        {posts.map((p) => (
          <div
            key={p.id}
            className="p-3.5 rounded-2xl bg-white dark:bg-[#1a1f24] border border-zinc-200/80 dark:border-zinc-800 shadow-xs space-y-2.5"
          >
            <div className="flex items-center justify-between">
              <div className="flex items-center gap-2">
                <div className="w-8 h-8 rounded-full bg-[#1877f2]/10 text-[#1877f2] font-bold text-xs flex items-center justify-center">
                  {p.author.slice(0, 1)}
                </div>
                <div>
                  <h4 className="text-xs font-bold">{p.author}</h4>
                  <span className="text-[10px] text-zinc-400">{p.time}</span>
                </div>
              </div>
              <button className="text-zinc-400 hover:text-zinc-600">
                <MoreHorizontal className="w-4 h-4" />
              </button>
            </div>

            <p className="text-xs leading-relaxed text-zinc-800 dark:text-zinc-200">{p.content}</p>

            <div className="pt-2 border-t border-zinc-100 dark:border-zinc-800 flex items-center justify-around text-xs text-zinc-500">
              <button
                onClick={() => handleLike(p.id)}
                className={`flex items-center gap-1.5 ${
                  p.isLiked ? 'text-rose-500 font-bold' : 'hover:text-zinc-800'
                }`}
              >
                <Heart className={`w-4 h-4 ${p.isLiked ? 'fill-current' : ''}`} />
                <span>{p.likes}</span>
              </button>
              <button className="flex items-center gap-1.5 hover:text-zinc-800">
                <MessageCircle className="w-4 h-4" />
                <span>{p.comments}</span>
              </button>
              <button className="flex items-center gap-1.5 hover:text-zinc-800">
                <Share2 className="w-4 h-4" />
                <span>Chia sẻ</span>
              </button>
            </div>
          </div>
        ))}
      </div>
    </div>
  );
};
