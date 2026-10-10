import React, { useState, useEffect } from 'react';
import {
  ChevronLeft,
  Plus,
  Trash2,
  FileText,
  AlertCircle,
} from 'lucide-react';
import { LocalVaultRepository } from '../../vault/vaultRepository';
import { VaultItem } from '../../../types';

interface SecureNotesAppViewProps {
  onBack: () => void;
  repository: LocalVaultRepository;
}

export const SecureNotesAppView: React.FC<SecureNotesAppViewProps> = ({
  onBack,
  repository,
}) => {
  const [notes, setNotes] = useState<VaultItem[]>([]);
  const [selectedNote, setSelectedNote] = useState<VaultItem | null>(null);
  const [noteContent, setNoteContent] = useState('');
  const [noteTitle, setNoteTitle] = useState('');
  const [isEditing, setIsEditing] = useState(false);
  const [saveError, setSaveError] = useState<string | null>(null);
  const [isSaving, setIsSaving] = useState(false);

  const loadNotes = async () => {
    try {
      const all = await repository.list();
      setNotes(all.filter((i) => i.kind === 'note'));
    } catch (e) {
      console.error(e);
    }
  };

  useEffect(() => {
    loadNotes();
  }, [repository]);

  const handleOpenNote = async (item: VaultItem) => {
    setSelectedNote(item);
    setNoteTitle(item.name || 'Ghi chú');
    setSaveError(null);
    try {
      const data = await repository.readBytes(item.id);
      setNoteContent(new TextDecoder().decode(data.bytes));
    } catch {
      setNoteContent('Không thể giải mã nội dung');
    }
    setIsEditing(false);
  };

  const handleCreateNewNote = () => {
    setSelectedNote(null);
    setNoteTitle('');
    setNoteContent('');
    setSaveError(null);
    setIsEditing(true);
  };

  const handleSaveNote = async () => {
    if (!noteContent.trim() && !noteTitle.trim()) return;
    const title = noteTitle.trim() || 'Ghi chú không tên';
    const bytes = new TextEncoder().encode(noteContent);
    setIsSaving(true);
    setSaveError(null);

    try {
      if (selectedNote) {
        // A04 fix: Atomic update without delete-before-save!
        await repository.updateNoteContent(selectedNote.id, bytes, title);
      } else {
        await repository.addBytes(bytes, {
          kind: 'note',
          name: title,
          album: 'Ghi chú',
        });
      }

      setIsEditing(false);
      setSelectedNote(null);
      await loadNotes();
    } catch (err) {
      console.error('Lỗi khi lưu ghi chú:', err);
      // Draft and existing note remain intact!
      setSaveError('Lưu ghi chú thất bại. Bản nháp và ghi chú gốc vẫn được giữ nguyên.');
    } finally {
      setIsSaving(false);
    }
  };

  const handleDeleteNote = async (item: VaultItem) => {
    if (!window.confirm('Xóa ghi chú này vĩnh viễn khỏi kho mã hóa?')) return;
    try {
      await repository.delete(item.id);
      if (selectedNote?.id === item.id) {
        setSelectedNote(null);
        setIsEditing(false);
      }
      await loadNotes();
    } catch (err) {
      alert('Không thể xóa ghi chú: ' + (err instanceof Error ? err.message : String(err)));
    }
  };

  return (
    <div className="flex flex-col h-full bg-[#f8f9fa] dark:bg-[#121416] text-zinc-900 dark:text-zinc-100 select-none overflow-hidden font-sans">
      {/* Header */}
      <div className="bg-amber-500 text-white px-3.5 py-3 flex items-center justify-between shadow-md shrink-0">
        <div className="flex items-center gap-2.5">
          <button
            onClick={selectedNote || isEditing ? () => { setSelectedNote(null); setIsEditing(false); setSaveError(null); } : onBack}
            className="p-1 rounded-full hover:bg-white/20"
          >
            <ChevronLeft className="w-5 h-5" />
          </button>
          <div>
            <h3 className="text-sm font-bold">
              {isEditing ? 'Soạn ghi chú' : selectedNote ? selectedNote.name : 'Ghi chú Bảo mật'}
            </h3>
            <p className="text-[10px] text-white/80">Mã hóa AES-256 trong Thư mục Bảo mật</p>
          </div>
        </div>

        <div className="flex items-center gap-2">
          {isEditing ? (
            <button
              onClick={handleSaveNote}
              disabled={isSaving}
              className="px-3 py-1 bg-white text-amber-600 font-bold rounded-lg text-xs hover:bg-white/90 disabled:opacity-50"
            >
              {isSaving ? 'Đang lưu...' : 'Lưu'}
            </button>
          ) : !selectedNote ? (
            <button
              onClick={handleCreateNewNote}
              className="p-1.5 rounded-lg bg-white/20 hover:bg-white/30 flex items-center gap-1 text-xs font-semibold"
            >
              <Plus className="w-4 h-4" />
              <span>Ghi chú mới</span>
            </button>
          ) : (
            <button
              onClick={() => setIsEditing(true)}
              className="px-3 py-1 bg-white/20 text-white font-semibold rounded-lg text-xs hover:bg-white/30"
            >
              Sửa
            </button>
          )}
        </div>
      </div>

      {saveError && (
        <div className="p-3 bg-rose-50 dark:bg-rose-950/60 border-b border-rose-200 dark:border-rose-900 text-rose-700 dark:text-rose-300 text-xs flex items-center gap-2">
          <AlertCircle className="w-4 h-4 shrink-0" />
          <span>{saveError}</span>
        </div>
      )}

      {/* Body */}
      {isEditing ? (
        <div className="flex-1 flex flex-col p-4 space-y-3 bg-white dark:bg-[#1a1d20]">
          <input
            type="text"
            value={noteTitle}
            onChange={(e) => setNoteTitle(e.target.value)}
            placeholder="Tiêu đề ghi chú..."
            className="text-base font-bold bg-transparent text-zinc-900 dark:text-zinc-100 placeholder-zinc-400 focus:outline-none border-b border-zinc-200 dark:border-zinc-800 pb-2"
            autoFocus
          />
          <textarea
            value={noteContent}
            onChange={(e) => setNoteContent(e.target.value)}
            placeholder="Nội dung ghi chú bí mật được mã hóa an toàn..."
            rows={15}
            className="flex-1 bg-transparent text-sm text-zinc-800 dark:text-zinc-200 placeholder-zinc-400 focus:outline-none resize-none leading-relaxed"
          />
        </div>
      ) : selectedNote ? (
        <div className="flex-1 flex flex-col p-4 bg-white dark:bg-[#1a1d20] overflow-y-auto space-y-3">
          <div className="flex items-center justify-between pb-2 border-b border-zinc-200 dark:border-zinc-800">
            <div>
              <h2 className="text-base font-bold text-zinc-900 dark:text-zinc-100">{noteTitle}</h2>
              <span className="text-[10px] text-zinc-400">
                {new Date(selectedNote.createdAt).toLocaleString()}
              </span>
            </div>
            <button
              onClick={() => handleDeleteNote(selectedNote)}
              className="p-2 text-rose-500 hover:bg-rose-50 dark:hover:bg-rose-950/40 rounded-xl"
              title="Xóa ghi chú"
            >
              <Trash2 className="w-4 h-4" />
            </button>
          </div>
          <div className="flex-1 text-sm text-zinc-800 dark:text-zinc-200 whitespace-pre-wrap leading-relaxed">
            {noteContent}
          </div>
        </div>
      ) : (
        <div className="flex-1 overflow-y-auto p-3 space-y-2.5">
          {notes.length === 0 ? (
            <div className="flex flex-col items-center justify-center py-20 text-center text-zinc-400 space-y-3">
              <FileText className="w-10 h-10 text-amber-500/60" />
              <p className="text-xs font-semibold text-zinc-600 dark:text-zinc-400">
                Chưa có ghi chú bảo mật nào
              </p>
              <button
                onClick={handleCreateNewNote}
                className="px-4 py-2 rounded-xl bg-amber-500 text-white font-semibold text-xs shadow-xs"
              >
                + Viết ghi chú đầu tiên
              </button>
            </div>
          ) : (
            notes.map((n) => (
              <div
                key={n.id}
                onClick={() => handleOpenNote(n)}
                className="p-3.5 rounded-2xl bg-white dark:bg-[#1a1d20] border border-zinc-200/80 dark:border-zinc-800 hover:border-amber-400 cursor-pointer transition-all flex items-center justify-between shadow-xs"
              >
                <div className="flex items-center gap-3 min-w-0">
                  <div className="w-9 h-9 rounded-xl bg-amber-500/10 text-amber-500 flex items-center justify-center shrink-0">
                    <FileText className="w-5 h-5" />
                  </div>
                  <div className="min-w-0">
                    <h4 className="text-xs font-bold text-zinc-900 dark:text-zinc-100 truncate">
                      {n.name || 'Ghi chú'}
                    </h4>
                    <p className="text-[10px] text-zinc-400 mt-0.5">
                      {new Date(n.createdAt).toLocaleDateString()}
                    </p>
                  </div>
                </div>
                <button
                  onClick={(e) => {
                    e.stopPropagation();
                    handleDeleteNote(n);
                  }}
                  className="p-1.5 text-zinc-400 hover:text-rose-500"
                >
                  <Trash2 className="w-4 h-4" />
                </button>
              </div>
            ))
          )}
        </div>
      )}
    </div>
  );
};
