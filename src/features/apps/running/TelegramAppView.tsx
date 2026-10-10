import React, { useState } from 'react';
import {
  Send,
  Image as ImageIcon,
  ChevronLeft,
  ExternalLink,
  Flame,
  CheckCheck,
  Paperclip,
} from 'lucide-react';
import { VaultItem } from '../../../types';

interface TelegramAppViewProps {
  onBack: () => void;
  vaultMedia?: VaultItem[];
}

export const TelegramAppView: React.FC<TelegramAppViewProps> = ({ onBack, vaultMedia = [] }) => {
  const [activeChatId, setActiveChatId] = useState<string | null>(null);
  const [inputMessage, setInputMessage] = useState('');
  const [isMediaPickerOpen, setIsMediaPickerOpen] = useState(false);
  const [secretTimer, setSecretTimer] = useState<number>(0);

  const [chats, setChats] = useState([
    {
      id: 'tg-1',
      name: 'Secret Chat 🔒',
      lastMsg: 'Self-destruct timer set to 30 seconds',
      time: '15:10',
      unread: 1,
      isSecret: true,
      avatarColor: '#24A1DE',
      messages: [
        {
          id: 't1',
          sender: 'other' as const,
          text: 'This is an end-to-end encrypted secret chat in Samsung Secure Folder profile.',
          time: '15:05',
        },
        {
          id: 't2',
          sender: 'me' as const,
          text: 'All messages and cryptographic session keys reside strictly in memory and isolated storage.',
          time: '15:08',
        },
      ],
    },
    {
      id: 'tg-2',
      name: 'Saved Messages (Cloud)',
      lastMsg: 'Private API keys and recovery backup codes',
      time: '12:30',
      unread: 0,
      isSecret: false,
      avatarColor: '#10b981',
      messages: [
        {
          id: 't3',
          sender: 'me' as const,
          text: 'Private API keys and recovery backup codes: 0x9482...bfa',
          time: '12:30',
        },
      ],
    },
    {
      id: 'tg-3',
      name: 'VIP Crypto Signals',
      lastMsg: 'BTC breakout target: $98,500',
      time: '10:14',
      unread: 4,
      isSecret: false,
      avatarColor: '#f59e0b',
      messages: [
        {
          id: 't4',
          sender: 'other' as const,
          text: 'BTC breakout target: $98,500 with strong volume confirmation.',
          time: '10:14',
        },
      ],
    },
  ]);

  const activeChat = chats.find((c) => c.id === activeChatId);

  const handleSendMessage = () => {
    if (!inputMessage.trim() || !activeChatId) return;

    const newMsg = {
      id: `tg-msg-${Date.now()}`,
      sender: 'me' as const,
      text: inputMessage.trim(),
      time: new Date().toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' }),
    };

    setChats((prev) =>
      prev.map((c) => {
        if (c.id === activeChatId) {
          return {
            ...c,
            lastMsg: newMsg.text,
            time: newMsg.time,
            messages: [...c.messages, newMsg],
          };
        }
        return c;
      })
    );

    setInputMessage('');

    if (activeChat?.isSecret) {
      setTimeout(() => {
        const reply = {
          id: `tg-reply-${Date.now()}`,
          sender: 'other' as const,
          text: 'Encrypted message acknowledged. Session secured.',
          time: new Date().toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' }),
        };
        setChats((prev) =>
          prev.map((c) => (c.id === activeChatId ? { ...c, messages: [...c.messages, reply] } : c))
        );
      }, 1000);
    }
  };

  const handleSendVaultMedia = (item: VaultItem) => {
    if (!activeChatId) return;
    const newMsg = {
      id: `tg-media-${Date.now()}`,
      sender: 'me' as const,
      text: `[Attached Vault Media]: ${item.name || 'Encrypted Image'}`,
      time: new Date().toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' }),
    };
    setChats((prev) =>
      prev.map((c) => (c.id === activeChatId ? { ...c, messages: [...c.messages, newMsg] } : c))
    );
    setIsMediaPickerOpen(false);
  };

  return (
    <div className="flex flex-col h-full bg-[#182533] text-white select-none overflow-hidden font-sans">
      {/* Top Telegram Header */}
      <div className="bg-[#242f3d] px-3.5 py-3 flex items-center justify-between border-b border-[#17212b] shrink-0 shadow-md">
        <div className="flex items-center gap-2.5">
          <button
            onClick={activeChat ? () => setActiveChatId(null) : onBack}
            className="p-1 rounded-full hover:bg-white/10 transition-colors"
          >
            <ChevronLeft className="w-5 h-5 text-[#6c7883]" />
          </button>
          <div>
            <div className="flex items-center gap-1.5">
              <h3 className="text-sm font-bold truncate max-w-[170px]">
                {activeChat ? activeChat.name : 'Telegram'}
              </h3>
              <span className="text-[10px] px-1.5 py-0.2 rounded bg-sky-500/20 text-sky-400 font-mono">
                Clone UID 10
              </span>
            </div>
            <p className="text-[10px] text-[#6c7883]">
              {activeChat?.isSecret ? 'Secret E2E Encryption' : 'Dual Account Sandbox'}
            </p>
          </div>
        </div>

        <div className="flex items-center gap-2">
          {activeChat?.isSecret && (
            <button
              onClick={() => setSecretTimer((t) => (t === 0 ? 30 : t === 30 ? 60 : 0))}
              className={`p-1.5 rounded-lg flex items-center gap-1 text-[11px] font-mono ${
                secretTimer > 0 ? 'bg-amber-500/20 text-amber-400' : 'text-[#6c7883]'
              }`}
              title="Self-destruct timer"
            >
              <Flame className="w-3.5 h-3.5" />
              {secretTimer > 0 && <span>{secretTimer}s</span>}
            </button>
          )}

          <a
            href="https://web.telegram.org"
            target="_blank"
            rel="noopener noreferrer"
            className="text-[11px] bg-white/10 hover:bg-white/20 text-zinc-200 px-2.5 py-1 rounded-lg flex items-center gap-1 transition-colors"
            title="Open Telegram Web"
          >
            <span>Web</span>
            <ExternalLink className="w-3 h-3" />
          </a>
        </div>
      </div>

      {/* Main View: Chat or Chat List */}
      {activeChat ? (
        <div className="flex-1 flex flex-col overflow-hidden bg-[#0e1621]">
          {/* Chat Messages */}
          <div className="flex-1 overflow-y-auto p-3.5 space-y-3">
            {activeChat.messages.map((m) => (
              <div
                key={m.id}
                className={`flex flex-col ${m.sender === 'me' ? 'items-end' : 'items-start'}`}
              >
                <div
                  className={`max-w-[80%] px-3.5 py-2 rounded-2xl text-xs shadow-xs break-words ${
                    m.sender === 'me'
                      ? 'bg-[#2b5278] text-white rounded-tr-xs'
                      : 'bg-[#182533] text-[#f5f5f5] rounded-tl-xs border border-[#232e3c]'
                  }`}
                >
                  <p className="leading-relaxed">{m.text}</p>
                  <div className="text-[9px] text-[#6c7883] mt-1 flex items-center justify-end gap-1">
                    <span>{m.time}</span>
                    {m.sender === 'me' && <CheckCheck className="w-3 h-3 text-[#24A1DE]" />}
                  </div>
                </div>
              </div>
            ))}
          </div>

          {/* Media Picker Drawer */}
          {isMediaPickerOpen && (
            <div className="p-3 bg-[#17212b] border-t border-[#232e3c] max-h-40 overflow-y-auto">
              <div className="flex items-center justify-between mb-2">
                <span className="text-xs font-bold text-zinc-300">
                  Select Vault Image ({vaultMedia.length})
                </span>
                <button
                  onClick={() => setIsMediaPickerOpen(false)}
                  className="text-xs text-zinc-500 hover:text-white"
                >
                  Close
                </button>
              </div>

              {vaultMedia.length === 0 ? (
                <p className="text-xs text-zinc-500 py-1">No media in Vault Gallery.</p>
              ) : (
                <div className="grid grid-cols-4 gap-2">
                  {vaultMedia.map((vm) => (
                    <button
                      key={vm.id}
                      onClick={() => handleSendVaultMedia(vm)}
                      className="p-2 rounded-xl bg-[#242f3d] border border-zinc-700 text-left hover:border-sky-400"
                    >
                      <ImageIcon className="w-4 h-4 text-sky-400 mb-1" />
                      <p className="text-[10px] truncate">{vm.name || 'Image'}</p>
                    </button>
                  ))}
                </div>
              )}
            </div>
          )}

          {/* Input Bar */}
          <div className="p-2.5 bg-[#17212b] border-t border-[#232e3c] flex items-center gap-2">
            <button
              onClick={() => setIsMediaPickerOpen(!isMediaPickerOpen)}
              className="p-2 text-[#6c7883] hover:text-[#24A1DE] transition-colors"
            >
              <Paperclip className="w-4 h-4" />
            </button>
            <input
              type="text"
              value={inputMessage}
              onChange={(e) => setInputMessage(e.target.value)}
              onKeyDown={(e) => e.key === 'Enter' && handleSendMessage()}
              placeholder="Write a message..."
              className="flex-1 bg-[#242f3d] px-3.5 py-2 rounded-2xl text-xs text-white placeholder-[#6c7883] focus:outline-none"
            />
            <button
              onClick={handleSendMessage}
              disabled={!inputMessage.trim()}
              className="p-2 rounded-full bg-[#24A1DE] text-white disabled:opacity-40 hover:opacity-90"
            >
              <Send className="w-4 h-4" />
            </button>
          </div>
        </div>
      ) : (
        /* Conversations List */
        <div className="flex-1 overflow-y-auto divide-y divide-[#17212b] bg-[#182533]">
          {chats.map((c) => (
            <div
              key={c.id}
              onClick={() => setActiveChatId(c.id)}
              className="p-3.5 flex items-center justify-between hover:bg-[#202b36] cursor-pointer transition-colors"
            >
              <div className="flex items-center gap-3 min-w-0">
                <div
                  className="w-11 h-11 rounded-full flex items-center justify-center font-bold text-white text-sm shadow-xs shrink-0"
                  style={{ backgroundColor: c.avatarColor }}
                >
                  {c.name.slice(0, 1)}
                </div>
                <div className="min-w-0">
                  <h4 className="text-xs font-bold text-white truncate">{c.name}</h4>
                  <p className="text-[11px] text-[#6c7883] truncate mt-0.5">{c.lastMsg}</p>
                </div>
              </div>

              <div className="flex flex-col items-end gap-1 shrink-0">
                <span className="text-[10px] text-[#6c7883]">{c.time}</span>
                {c.unread > 0 && (
                  <span className="px-1.5 py-0.2 rounded-full bg-[#24A1DE] text-white text-[10px] font-bold">
                    {c.unread}
                  </span>
                )}
              </div>
            </div>
          ))}
        </div>
      )}
    </div>
  );
};
