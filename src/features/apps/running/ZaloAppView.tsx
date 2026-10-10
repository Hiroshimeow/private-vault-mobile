import React, { useState } from 'react';
import {
  Send,
  Image as ImageIcon,
  Phone,
  Video as VideoIcon,
  Search,
  MoreVertical,
  ChevronLeft,
  ExternalLink,
  MessageCircle,
  Users,
  Compass,
  Clock,
  User,
  Shield,
  CheckCheck,
} from 'lucide-react';
import { VaultItem } from '../../../types';

interface ZaloAppViewProps {
  onBack: () => void;
  vaultMedia?: VaultItem[];
}

interface Message {
  id: string;
  sender: 'me' | 'other';
  text: string;
  time: string;
  imageUrl?: string;
  isEncrypted?: boolean;
}

interface Conversation {
  id: string;
  name: string;
  lastMessage: string;
  time: string;
  unread: number;
  avatarColor: string;
  isSecret: boolean;
  messages: Message[];
}

export const ZaloAppView: React.FC<ZaloAppViewProps> = ({ onBack, vaultMedia = [] }) => {
  const [currentTab, setCurrentTab] = useState<'chats' | 'contacts' | 'discover' | 'timeline' | 'profile'>('chats');
  const [activeChatId, setActiveChatId] = useState<string | null>(null);

  const [inputMessage, setInputMessage] = useState('');
  const [isMediaPickerOpen, setIsMediaPickerOpen] = useState(false);

  const [conversations, setConversations] = useState<Conversation[]>([
    {
      id: 'chat-1',
      name: 'Dự án bí mật 🔒',
      lastMessage: 'Tài liệu đã được mã hóa vào thư mục an toàn.',
      time: '14:20',
      unread: 2,
      avatarColor: '#0068ff',
      isSecret: true,
      messages: [
        {
          id: 'm1',
          sender: 'other' as const,
          text: 'Chào anh, đây là kênh liên lạc phụ trong Thư mục bảo mật.',
          time: '14:15',
          isEncrypted: true,
        },
        {
          id: 'm2',
          sender: 'me' as const,
          text: 'Đã nhận. Toàn bộ hình ảnh và dữ liệu ở đây được cách ly với Zalo chính.',
          time: '14:18',
          isEncrypted: true,
        },
        {
          id: 'm3',
          sender: 'other' as const,
          text: 'Tài liệu đã được mã hóa vào thư mục an toàn.',
          time: '14:20',
          isEncrypted: true,
        },
      ],
    },
    {
      id: 'chat-2',
      name: 'Nguyễn Văn Hùng (Đối tác VIP)',
      lastMessage: 'Hợp đồng mới đã ký, anh kiểm tra giúp tôi nhé.',
      time: '11:45',
      unread: 0,
      avatarColor: '#059669',
      isSecret: false,
      messages: [
        {
          id: 'm4',
          sender: 'other' as const,
          text: 'Hợp đồng mới đã ký, anh kiểm tra giúp tôi nhé.',
          time: '11:45',
        },
      ],
    },
    {
      id: 'chat-3',
      name: 'Cloud của tôi (Lưu trữ riêng tư)',
      lastMessage: 'Ghi chú mật khẩu ngân hàng và mã PIN dự phòng.',
      time: 'Hôm qua',
      unread: 0,
      avatarColor: '#7c3aed',
      isSecret: true,
      messages: [
        {
          id: 'm5',
          sender: 'me' as const,
          text: 'Ghi chú mật khẩu ngân hàng và mã PIN dự phòng.',
          time: 'Hôm qua',
        },
      ],
    },
    {
      id: 'chat-4',
      name: 'Gia đình',
      lastMessage: 'Tối nay cả nhà ăn cơm lúc 7h nhé!',
      time: 'Thứ 3',
      unread: 0,
      avatarColor: '#ea580c',
      isSecret: false,
      messages: [
        {
          id: 'm6',
          sender: 'other' as const,
          text: 'Tối nay cả nhà ăn cơm lúc 7h nhé!',
          time: 'Thứ 3',
        },
      ],
    },
  ]);

  const activeChat = conversations.find((c) => c.id === activeChatId);

  const handleSendMessage = () => {
    if (!inputMessage.trim() || !activeChatId) return;

    const newMsg: Message = {
      id: `msg-${Date.now()}`,
      sender: 'me',
      text: inputMessage.trim(),
      time: new Date().toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' }),
      isEncrypted: activeChat?.isSecret,
    };

    setConversations((prev) =>
      prev.map((c) => {
        if (c.id === activeChatId) {
          return {
            ...c,
            lastMessage: newMsg.text,
            time: newMsg.time,
            messages: [...c.messages, newMsg],
          };
        }
        return c;
      })
    );

    setInputMessage('');

    // Simulate auto-reply if chatting in secret chat
    if (activeChat?.isSecret) {
      setTimeout(() => {
        const reply: Message = {
          id: `reply-${Date.now()}`,
          sender: 'other',
          text: 'Đã nhận thông điệp an toàn. Dữ liệu được lưu trong Sandbox.',
          time: new Date().toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' }),
          isEncrypted: true,
        };
        setConversations((prev) =>
          prev.map((c) => (c.id === activeChatId ? { ...c, messages: [...c.messages, reply] } : c))
        );
      }, 1200);
    }
  };

  const handleSendVaultMedia = (item: VaultItem) => {
    if (!activeChatId) return;
    const newMsg: Message = {
      id: `media-${Date.now()}`,
      sender: 'me',
      text: `[Đính kèm từ Thư mục Bảo mật]: ${item.name || 'Ảnh mã hóa'}`,
      time: new Date().toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' }),
      isEncrypted: true,
    };
    setConversations((prev) =>
      prev.map((c) => (c.id === activeChatId ? { ...c, messages: [...c.messages, newMsg] } : c))
    );
    setIsMediaPickerOpen(false);
  };

  return (
    <div className="flex flex-col h-full bg-[#f4f5f7] dark:bg-[#121214] text-zinc-900 dark:text-zinc-100 select-none overflow-hidden font-sans">
      {/* Top Zalo App Bar */}
      <div className="bg-[#0068ff] text-white px-3 py-2.5 flex items-center justify-between shadow-md shrink-0">
        <div className="flex items-center gap-2">
          {activeChat ? (
            <button
              onClick={() => setActiveChatId(null)}
              className="p-1 rounded-full hover:bg-white/20 transition-colors"
            >
              <ChevronLeft className="w-5 h-5" />
            </button>
          ) : (
            <button
              onClick={onBack}
              className="p-1 rounded-full hover:bg-white/20 transition-colors"
              title="Quay lại Thư mục Bảo mật"
            >
              <ChevronLeft className="w-5 h-5" />
            </button>
          )}

          <div className="flex items-center gap-1.5">
            <span className="font-bold text-sm tracking-tight">
              {activeChat ? activeChat.name : 'Zalo'}
            </span>
            <span className="text-[10px] px-1.5 py-0.2 rounded bg-white/25 font-semibold text-white">
              Tài khoản 2
            </span>
          </div>
        </div>

        <div className="flex items-center gap-2">
          {activeChat ? (
            <>
              <button className="p-1.5 rounded-full hover:bg-white/20">
                <Phone className="w-4 h-4" />
              </button>
              <button className="p-1.5 rounded-full hover:bg-white/20">
                <VideoIcon className="w-4 h-4" />
              </button>
              <button className="p-1.5 rounded-full hover:bg-white/20">
                <MoreVertical className="w-4 h-4" />
              </button>
            </>
          ) : (
            <>
              <a
                href="https://chat.zalo.me"
                target="_blank"
                rel="noopener noreferrer"
                className="text-[11px] bg-white/20 hover:bg-white/30 text-white px-2 py-1 rounded-lg flex items-center gap-1 transition-colors"
                title="Mở Zalo Web trong tab mới"
              >
                <span>Zalo Web</span>
                <ExternalLink className="w-3 h-3" />
              </a>
            </>
          )}
        </div>
      </div>

      {/* Main View: Active Chat Room or Conversations List */}
      {activeChat ? (
        <div className="flex-1 flex flex-col overflow-hidden bg-[#eef0f3] dark:bg-[#18181b]">
          {/* Secret notification banner */}
          {activeChat.isSecret && (
            <div className="px-3 py-1.5 bg-teal-50 dark:bg-teal-950/60 border-b border-teal-200 dark:border-teal-900/50 flex items-center justify-between text-[11px] text-teal-800 dark:text-teal-300">
              <div className="flex items-center gap-1.5 font-medium">
                <Shield className="w-3.5 h-3.5 text-teal-600 dark:text-teal-400" />
                <span>Trò chuyện bảo mật riêng tư trong Thư mục Vault</span>
              </div>
              <span className="font-mono text-[10px]">Tài khoản độc lập</span>
            </div>
          )}

          {/* Messages list */}
          <div className="flex-1 overflow-y-auto p-3 space-y-3">
            {activeChat.messages.map((m) => (
              <div
                key={m.id}
                className={`flex flex-col ${m.sender === 'me' ? 'items-end' : 'items-start'}`}
              >
                <div
                  className={`max-w-[78%] px-3.5 py-2 rounded-2xl text-xs shadow-xs break-words ${
                    m.sender === 'me'
                      ? 'bg-[#0068ff] text-white rounded-tr-xs'
                      : 'bg-white dark:bg-zinc-800 text-zinc-900 dark:text-zinc-100 rounded-tl-xs border border-zinc-200/80 dark:border-zinc-700/80'
                  }`}
                >
                  <p className="leading-relaxed">{m.text}</p>
                  <div
                    className={`text-[9px] mt-1 flex items-center justify-end gap-1 ${
                      m.sender === 'me' ? 'text-white/80' : 'text-zinc-400'
                    }`}
                  >
                    <span>{m.time}</span>
                    {m.sender === 'me' && <CheckCheck className="w-3 h-3" />}
                  </div>
                </div>
              </div>
            ))}
          </div>

          {/* Media Picker Drawer */}
          {isMediaPickerOpen && (
            <div className="p-3 bg-white dark:bg-zinc-900 border-t border-zinc-200 dark:border-zinc-800 max-h-40 overflow-y-auto animate-in slide-in-from-bottom">
              <div className="flex items-center justify-between mb-2">
                <span className="text-xs font-bold text-zinc-700 dark:text-zinc-300">
                  Chọn ảnh từ Thư mục Bảo mật ({vaultMedia.length})
                </span>
                <button
                  onClick={() => setIsMediaPickerOpen(false)}
                  className="text-xs text-zinc-400 hover:text-zinc-600"
                >
                  Đóng
                </button>
              </div>

              {vaultMedia.length === 0 ? (
                <p className="text-xs text-zinc-400 py-2">
                  Chưa có ảnh trong Vault Gallery. Hãy thêm ảnh vào Thư mục Bảo mật trước.
                </p>
              ) : (
                <div className="grid grid-cols-4 gap-2">
                  {vaultMedia.map((vm) => (
                    <button
                      key={vm.id}
                      onClick={() => handleSendVaultMedia(vm)}
                      className="p-2 rounded-xl bg-zinc-100 dark:bg-zinc-800 border border-zinc-300 dark:border-zinc-700 text-left hover:border-[#0068ff] transition-all"
                    >
                      <ImageIcon className="w-4 h-4 text-[#0068ff] mb-1" />
                      <p className="text-[10px] font-medium truncate">{vm.name || 'Ảnh'}</p>
                    </button>
                  ))}
                </div>
              )}
            </div>
          )}

          {/* Input Bar */}
          <div className="p-2.5 bg-white dark:bg-zinc-900 border-t border-zinc-200 dark:border-zinc-800 flex items-center gap-2">
            <button
              onClick={() => setIsMediaPickerOpen(!isMediaPickerOpen)}
              className="p-2 rounded-xl text-zinc-500 hover:text-[#0068ff] hover:bg-zinc-100 dark:hover:bg-zinc-800"
              title="Đính kèm từ Vault Gallery"
            >
              <ImageIcon className="w-4 h-4" />
            </button>
            <input
              type="text"
              value={inputMessage}
              onChange={(e) => setInputMessage(e.target.value)}
              onKeyDown={(e) => e.key === 'Enter' && handleSendMessage()}
              placeholder="Tin nhắn bí mật..."
              className="flex-1 bg-zinc-100 dark:bg-zinc-800 px-3 py-2 rounded-xl text-xs text-zinc-900 dark:text-zinc-100 focus:outline-none focus:ring-1 focus:ring-[#0068ff]"
            />
            <button
              onClick={handleSendMessage}
              disabled={!inputMessage.trim()}
              className="p-2 rounded-xl bg-[#0068ff] text-white disabled:opacity-40 hover:bg-[#0052cc] transition-colors"
            >
              <Send className="w-4 h-4" />
            </button>
          </div>
        </div>
      ) : (
        /* Conversation List */
        <div className="flex-1 flex flex-col overflow-hidden">
          {/* Search bar inside Zalo */}
          <div className="px-3 py-2 bg-white dark:bg-zinc-900 border-b border-zinc-200 dark:border-zinc-800 flex items-center gap-2">
            <Search className="w-4 h-4 text-zinc-400" />
            <input
              type="text"
              placeholder="Tìm kiếm tin nhắn, danh bạ..."
              className="w-full bg-transparent text-xs text-zinc-800 dark:text-zinc-200 placeholder-zinc-400 focus:outline-none"
            />
          </div>

          <div className="flex-1 overflow-y-auto divide-y divide-zinc-100 dark:divide-zinc-800/60 bg-white dark:bg-zinc-900">
            {conversations.map((conv) => (
              <div
                key={conv.id}
                onClick={() => setActiveChatId(conv.id)}
                className="p-3 flex items-center justify-between hover:bg-zinc-50 dark:hover:bg-zinc-800/50 cursor-pointer transition-colors"
              >
                <div className="flex items-center gap-3 min-w-0">
                  <div
                    className="w-11 h-11 rounded-full flex items-center justify-center font-bold text-white text-sm shadow-xs shrink-0 relative"
                    style={{ backgroundColor: conv.avatarColor }}
                  >
                    {conv.name.slice(0, 1)}
                    {conv.isSecret && (
                      <div className="absolute -bottom-0.5 -right-0.5 w-4 h-4 rounded-full bg-teal-500 border-2 border-white dark:border-zinc-900 flex items-center justify-center text-white">
                        <Shield className="w-2.5 h-2.5" />
                      </div>
                    )}
                  </div>
                  <div className="min-w-0">
                    <div className="flex items-center gap-1.5">
                      <h4 className="text-xs font-bold text-zinc-900 dark:text-zinc-100 truncate">
                        {conv.name}
                      </h4>
                    </div>
                    <p className="text-[11px] text-zinc-500 dark:text-zinc-400 truncate max-w-[210px] mt-0.5">
                      {conv.lastMessage}
                    </p>
                  </div>
                </div>

                <div className="flex flex-col items-end gap-1 shrink-0">
                  <span className="text-[10px] text-zinc-400">{conv.time}</span>
                  {conv.unread > 0 && (
                    <span className="px-1.5 py-0.2 rounded-full bg-rose-500 text-white text-[10px] font-bold">
                      {conv.unread}
                    </span>
                  )}
                </div>
              </div>
            ))}
          </div>

          {/* Zalo Bottom Navigation Tabs */}
          <div className="h-14 bg-white dark:bg-zinc-900 border-t border-zinc-200 dark:border-zinc-800 flex items-center justify-around px-2 shrink-0">
            <button
              onClick={() => setCurrentTab('chats')}
              className={`flex flex-col items-center gap-1 text-[10px] ${
                currentTab === 'chats' ? 'text-[#0068ff] font-bold' : 'text-zinc-400'
              }`}
            >
              <MessageCircle className="w-5 h-5" />
              <span>Tin nhắn</span>
            </button>
            <button
              onClick={() => setCurrentTab('contacts')}
              className={`flex flex-col items-center gap-1 text-[10px] ${
                currentTab === 'contacts' ? 'text-[#0068ff] font-bold' : 'text-zinc-400'
              }`}
            >
              <Users className="w-5 h-5" />
              <span>Danh bạ</span>
            </button>
            <button
              onClick={() => setCurrentTab('discover')}
              className={`flex flex-col items-center gap-1 text-[10px] ${
                currentTab === 'discover' ? 'text-[#0068ff] font-bold' : 'text-zinc-400'
              }`}
            >
              <Compass className="w-5 h-5" />
              <span>Khám phá</span>
            </button>
            <button
              onClick={() => setCurrentTab('timeline')}
              className={`flex flex-col items-center gap-1 text-[10px] ${
                currentTab === 'timeline' ? 'text-[#0068ff] font-bold' : 'text-zinc-400'
              }`}
            >
              <Clock className="w-5 h-5" />
              <span>Nhật ký</span>
            </button>
            <button
              onClick={() => setCurrentTab('profile')}
              className={`flex flex-col items-center gap-1 text-[10px] ${
                currentTab === 'profile' ? 'text-[#0068ff] font-bold' : 'text-zinc-400'
              }`}
            >
              <User className="w-5 h-5" />
              <span>Cá nhân</span>
            </button>
          </div>
        </div>
      )}
    </div>
  );
};
