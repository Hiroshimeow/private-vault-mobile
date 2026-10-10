import React, { useState } from 'react';
import {
  Send,
  Image as ImageIcon,
  ChevronLeft,
  ExternalLink,
  Phone,
  Video as VideoIcon,
  Paperclip,
  CheckCheck,
} from 'lucide-react';
import { VaultItem } from '../../../types';

interface WhatsAppAppViewProps {
  onBack: () => void;
  vaultMedia?: VaultItem[];
}

export const WhatsAppAppView: React.FC<WhatsAppAppViewProps> = ({ onBack, vaultMedia = [] }) => {
  const [activeChatId, setActiveChatId] = useState<string | null>(null);
  const [inputMessage, setInputMessage] = useState('');
  const [isMediaPickerOpen, setIsMediaPickerOpen] = useState(false);

  const [chats, setChats] = useState([
    {
      id: 'wa-1',
      name: 'Private Business Group',
      lastMsg: 'Quarterly review slides are locked.',
      time: '16:02',
      unread: 1,
      avatarColor: '#25D366',
      messages: [
        {
          id: 'w1',
          sender: 'other' as const,
          text: 'Welcome to WhatsApp Clone in Samsung Secure Folder profile.',
          time: '15:50',
        },
        {
          id: 'w2',
          sender: 'me' as const,
          text: 'Ready for encrypted communications.',
          time: '15:58',
        },
        {
          id: 'w3',
          sender: 'other' as const,
          text: 'Quarterly review slides are locked.',
          time: '16:02',
        },
      ],
    },
    {
      id: 'wa-2',
      name: 'Michael (Security Audit)',
      lastMsg: 'Verified zero cross-profile data leakage.',
      time: '13:15',
      unread: 0,
      avatarColor: '#128c7e',
      messages: [
        {
          id: 'w4',
          sender: 'other' as const,
          text: 'Verified zero cross-profile data leakage.',
          time: '13:15',
        },
      ],
    },
  ]);

  const activeChat = chats.find((c) => c.id === activeChatId);

  const handleSendMessage = () => {
    if (!inputMessage.trim() || !activeChatId) return;

    const newMsg = {
      id: `wa-msg-${Date.now()}`,
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
  };

  const handleSendVaultMedia = (item: VaultItem) => {
    if (!activeChatId) return;
    const newMsg = {
      id: `wa-media-${Date.now()}`,
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
    <div className="flex flex-col h-full bg-[#efeae2] dark:bg-[#0b141a] text-zinc-900 dark:text-zinc-100 select-none overflow-hidden font-sans">
      {/* Header */}
      <div className="bg-[#075e54] dark:bg-[#1f2c34] text-white px-3.5 py-3 flex items-center justify-between shrink-0 shadow-md">
        <div className="flex items-center gap-2.5">
          <button
            onClick={activeChat ? () => setActiveChatId(null) : onBack}
            className="p-1 rounded-full hover:bg-white/10"
          >
            <ChevronLeft className="w-5 h-5" />
          </button>
          <div>
            <div className="flex items-center gap-1.5">
              <h3 className="text-sm font-bold truncate max-w-[170px]">
                {activeChat ? activeChat.name : 'WhatsApp'}
              </h3>
              <span className="text-[10px] px-1.5 py-0.2 rounded bg-emerald-500/20 text-emerald-300 font-mono">
                Dual App
              </span>
            </div>
            <p className="text-[10px] text-zinc-300">End-to-end encrypted</p>
          </div>
        </div>

        <div className="flex items-center gap-2">
          {activeChat ? (
            <>
              <button className="p-1.5 rounded-full hover:bg-white/10">
                <VideoIcon className="w-4 h-4" />
              </button>
              <button className="p-1.5 rounded-full hover:bg-white/10">
                <Phone className="w-4 h-4" />
              </button>
            </>
          ) : (
            <a
              href="https://web.whatsapp.com"
              target="_blank"
              rel="noopener noreferrer"
              className="text-[11px] bg-white/15 hover:bg-white/25 text-white px-2.5 py-1 rounded-lg flex items-center gap-1"
            >
              <span>Web</span>
              <ExternalLink className="w-3 h-3" />
            </a>
          )}
        </div>
      </div>

      {/* Body */}
      {activeChat ? (
        <div className="flex-1 flex flex-col overflow-hidden bg-[#efeae2] dark:bg-[#0b141a]">
          <div className="flex-1 overflow-y-auto p-3.5 space-y-3">
            <div className="p-2 rounded-xl bg-amber-50 dark:bg-amber-950/40 border border-amber-200 dark:border-amber-900/40 text-center text-[10px] text-amber-800 dark:text-amber-200">
              🔒 Messages and calls are end-to-end encrypted inside Private Vault profile.
            </div>

            {activeChat.messages.map((m) => (
              <div
                key={m.id}
                className={`flex flex-col ${m.sender === 'me' ? 'items-end' : 'items-start'}`}
              >
                <div
                  className={`max-w-[78%] px-3.5 py-2 rounded-2xl text-xs shadow-xs break-words ${
                    m.sender === 'me'
                      ? 'bg-[#d9fdd3] dark:bg-[#005c4b] text-zinc-900 dark:text-white rounded-tr-xs'
                      : 'bg-white dark:bg-[#202c33] text-zinc-900 dark:text-white rounded-tl-xs border border-zinc-200 dark:border-zinc-800'
                  }`}
                >
                  <p className="leading-relaxed">{m.text}</p>
                  <div className="text-[9px] text-zinc-500 dark:text-zinc-400 mt-1 flex items-center justify-end gap-1">
                    <span>{m.time}</span>
                    {m.sender === 'me' && <CheckCheck className="w-3 h-3 text-[#53bdeb]" />}
                  </div>
                </div>
              </div>
            ))}
          </div>

          {/* Media Picker */}
          {isMediaPickerOpen && (
            <div className="p-3 bg-white dark:bg-[#202c33] border-t border-zinc-300 dark:border-zinc-700 max-h-40 overflow-y-auto">
              <div className="flex items-center justify-between mb-2">
                <span className="text-xs font-bold">Attach from Vault Gallery</span>
                <button
                  onClick={() => setIsMediaPickerOpen(false)}
                  className="text-xs text-zinc-400 hover:text-zinc-600"
                >
                  Close
                </button>
              </div>
              <div className="grid grid-cols-4 gap-2">
                {vaultMedia.map((vm) => (
                  <button
                    key={vm.id}
                    onClick={() => handleSendVaultMedia(vm)}
                    className="p-2 rounded-xl bg-zinc-100 dark:bg-[#111b21] border border-zinc-300 dark:border-zinc-700 text-left hover:border-emerald-500"
                  >
                    <ImageIcon className="w-4 h-4 text-emerald-500 mb-1" />
                    <p className="text-[10px] truncate">{vm.name || 'Photo'}</p>
                  </button>
                ))}
              </div>
            </div>
          )}

          {/* Input Bar */}
          <div className="p-2.5 bg-zinc-100 dark:bg-[#202c33] border-t border-zinc-300 dark:border-zinc-700 flex items-center gap-2">
            <button
              onClick={() => setIsMediaPickerOpen(!isMediaPickerOpen)}
              className="p-2 text-zinc-500 hover:text-emerald-500"
            >
              <Paperclip className="w-4 h-4" />
            </button>
            <input
              type="text"
              value={inputMessage}
              onChange={(e) => setInputMessage(e.target.value)}
              onKeyDown={(e) => e.key === 'Enter' && handleSendMessage()}
              placeholder="Type a message..."
              className="flex-1 bg-white dark:bg-[#2a3942] px-3.5 py-2 rounded-2xl text-xs text-zinc-900 dark:text-zinc-100 focus:outline-none"
            />
            <button
              onClick={handleSendMessage}
              disabled={!inputMessage.trim()}
              className="p-2 rounded-full bg-[#00a884] text-white disabled:opacity-40"
            >
              <Send className="w-4 h-4" />
            </button>
          </div>
        </div>
      ) : (
        <div className="flex-1 overflow-y-auto divide-y divide-zinc-200 dark:divide-zinc-800 bg-white dark:bg-[#111b21]">
          {chats.map((c) => (
            <div
              key={c.id}
              onClick={() => setActiveChatId(c.id)}
              className="p-3.5 flex items-center justify-between hover:bg-zinc-50 dark:hover:bg-[#202c33] cursor-pointer transition-colors"
            >
              <div className="flex items-center gap-3 min-w-0">
                <div
                  className="w-11 h-11 rounded-full flex items-center justify-center font-bold text-white text-sm shrink-0"
                  style={{ backgroundColor: c.avatarColor }}
                >
                  {c.name.slice(0, 1)}
                </div>
                <div className="min-w-0">
                  <h4 className="text-xs font-bold truncate">{c.name}</h4>
                  <p className="text-[11px] text-zinc-500 dark:text-zinc-400 truncate mt-0.5">
                    {c.lastMsg}
                  </p>
                </div>
              </div>

              <div className="flex flex-col items-end gap-1 shrink-0">
                <span className="text-[10px] text-zinc-400">{c.time}</span>
                {c.unread > 0 && (
                  <span className="px-1.5 py-0.2 rounded-full bg-[#25D366] text-zinc-900 text-[10px] font-bold">
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
