import React, { useState, useRef, useEffect } from 'react';
import { Plus, X, CheckCircle2, Circle } from 'lucide-react';

interface NotesCoverProps {
  onUnlockRequested: () => void;
  onAttemptPin?: (pin: string) => Promise<boolean> | boolean;
}

interface TodoItem {
  id: string;
  text: string;
  done: boolean;
}

const STORAGE_KEY = 'pv_benign_cover_notes_v1';

export const NotesCover: React.FC<NotesCoverProps> = ({ onUnlockRequested, onAttemptPin }) => {
  const [items, setItems] = useState<TodoItem[]>(() => {
    try {
      const raw = localStorage.getItem(STORAGE_KEY);
      if (raw) return JSON.parse(raw);
    } catch {}
    return [
      { id: '1', text: 'Mua sữa và thực phẩm tuần này', done: false },
      { id: '2', text: 'Xem lại hợp đồng công việc', done: true },
      { id: '3', text: 'Hẹn lịch khám răng định kỳ', done: false },
    ];
  });

  const [input, setInput] = useState('');
  const timerRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const [isPressing, setIsPressing] = useState(false);

  useEffect(() => {
    try {
      localStorage.setItem(STORAGE_KEY, JSON.stringify(items));
    } catch {}
  }, [items]);

  const startPress = (e: React.PointerEvent) => {
    e.preventDefault();
    setIsPressing(true);
    if (timerRef.current) clearTimeout(timerRef.current);
    timerRef.current = setTimeout(() => {
      setIsPressing(false);
      onUnlockRequested();
    }, 750);
  };

  const cancelPress = () => {
    setIsPressing(false);
    if (timerRef.current) {
      clearTimeout(timerRef.current);
      timerRef.current = null;
    }
  };

  useEffect(() => {
    return () => {
      if (timerRef.current) clearTimeout(timerRef.current);
    };
  }, []);

  const add = async (e?: React.FormEvent) => {
    if (e) e.preventDefault();
    const trimmed = input.trim();
    if (!trimmed) return;

    if (onAttemptPin && /^\d{4,12}$/.test(trimmed)) {
      try {
        const unlocked = await onAttemptPin(trimmed);
        if (unlocked) {
          setInput('');
          return;
        }
      } catch (err) {
        console.error('Notes PIN attempt error:', err);
      }
    }

    setItems((prev) => [...prev, { id: Date.now().toString(), text: trimmed, done: false }]);
    setInput('');
  };

  const toggle = (id: string) => {
    setItems((prev) =>
      prev.map((item) => (item.id === id ? { ...item, done: !item.done } : item))
    );
  };

  const remove = (id: string) => {
    setItems((prev) => prev.filter((item) => item.id !== id));
  };

  const remaining = items.filter((i) => !i.done).length;

  return (
    <div className="flex flex-col h-full w-full bg-zinc-50 dark:bg-[#101718] select-none">
      <header className="px-5 py-4 pt-[max(1rem,env(safe-area-inset-top))] border-b border-zinc-200/80 dark:border-zinc-800/80 flex items-center justify-between shrink-0">
        <div
          data-testid="cover-title"
          className={`cursor-pointer transition-opacity duration-200 select-none flex items-center ${
            isPressing ? 'opacity-60 scale-95' : 'opacity-100'
          }`}
          onPointerDown={startPress}
          onPointerUp={cancelPress}
          onPointerCancel={cancelPress}
          onPointerLeave={cancelPress}
        >
          <span className="text-xl font-bold tracking-tight text-zinc-800 dark:text-zinc-100">
            Notes
          </span>
        </div>
      </header>

      <div className="flex-1 overflow-y-auto px-5 py-4 pb-[max(1.5rem,env(safe-area-inset-bottom))] flex flex-col gap-4">
        <div>
          <h2 className="text-2xl font-bold tracking-tight text-zinc-900 dark:text-zinc-100">
            Hôm nay
          </h2>
          <p className="text-sm text-zinc-500 dark:text-zinc-400 mt-0.5">
            {items.length === 0
              ? 'Danh sách việc cần làm trong ngày.'
              : `${remaining} việc cần hoàn thành · ${items.length} tổng`}
          </p>
        </div>

        <form
          onSubmit={add}
          className="flex items-center gap-2 p-2 rounded-xl bg-white dark:bg-zinc-900 border border-zinc-200 dark:border-zinc-800 shadow-xs"
        >
          <input
            data-testid="todo-input"
            type="text"
            value={input}
            onChange={(e) => setInput(e.target.value)}
            placeholder="Thêm nhiệm vụ..."
            className="flex-1 px-3 py-1.5 bg-transparent text-sm focus:outline-none text-zinc-900 dark:text-zinc-100 placeholder-zinc-400"
          />
          <button
            type="submit"
            data-testid="todo-add"
            className="p-2 rounded-lg bg-[#315e63] dark:bg-[#78aeb3] text-white dark:text-zinc-950 hover:opacity-90 transition-opacity"
            aria-label="Thêm nhiệm vụ"
          >
            <Plus className="w-4 h-4" />
          </button>
        </form>

        <div className="flex-1 space-y-2">
          {items.length === 0 ? (
            <div className="py-12 text-center text-sm text-zinc-400">Không có ghi chú nào</div>
          ) : (
            items.map((item) => (
              <div
                key={item.id}
                className="flex items-center justify-between p-3 rounded-xl bg-white dark:bg-zinc-900/70 border border-zinc-200/80 dark:border-zinc-800/80 transition-all hover:border-zinc-300 shadow-xs"
              >
                <button
                  type="button"
                  onClick={() => toggle(item.id)}
                  className="flex items-center gap-3 flex-1 text-left"
                >
                  {item.done ? (
                    <CheckCircle2 className="w-5 h-5 text-teal-600 dark:text-teal-400 shrink-0" />
                  ) : (
                    <Circle className="w-5 h-5 text-zinc-300 dark:text-zinc-600 shrink-0" />
                  )}
                  <span
                    className={`text-sm ${
                      item.done
                        ? 'line-through text-zinc-400 dark:text-zinc-500'
                        : 'text-zinc-800 dark:text-zinc-200'
                    }`}
                  >
                    {item.text}
                  </span>
                </button>
                <button
                  type="button"
                  onClick={() => remove(item.id)}
                  className="p-1 text-zinc-400 hover:text-rose-500 transition-colors"
                  aria-label="Xóa"
                >
                  <X className="w-4 h-4" />
                </button>
              </div>
            ))
          )}
        </div>
      </div>
    </div>
  );
};
