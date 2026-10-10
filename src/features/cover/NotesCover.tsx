import React, { useState, useRef, useEffect } from 'react';
import { Plus, X, CheckCircle2, Circle } from 'lucide-react';

interface NotesCoverProps {
  onUnlockRequested: () => void;
}

interface TodoItem {
  id: string;
  text: string;
  done: boolean;
}

export const NotesCover: React.FC<NotesCoverProps> = ({ onUnlockRequested }) => {
  const [items, setItems] = useState<TodoItem[]>([
    { id: '1', text: 'Buy groceries (milk, eggs, fruit)', done: false },
    { id: '2', text: 'Review project notes', done: true },
    { id: '3', text: 'Call dentist for routine checkup', done: false },
  ]);
  const [input, setInput] = useState('');

  const timerRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const [isPressing, setIsPressing] = useState(false);

  const startPress = () => {
    setIsPressing(true);
    timerRef.current = setTimeout(() => {
      setIsPressing(false);
      onUnlockRequested();
    }, 700);
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

  const add = (e?: React.FormEvent) => {
    if (e) e.preventDefault();
    const trimmed = input.trim();
    if (!trimmed) return;
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
    <div className="flex flex-col h-full max-w-md mx-auto bg-zinc-50 dark:bg-[#101718] select-none">
      <header className="px-5 py-4 border-b border-zinc-200/80 dark:border-zinc-800/80 flex items-center justify-between">
        <div
          data-testid="cover-title"
          className={`cursor-pointer transition-all duration-300 select-none flex items-center gap-2 ${
            isPressing ? 'opacity-50 scale-95' : 'opacity-100'
          }`}
          onMouseDown={startPress}
          onMouseUp={cancelPress}
          onMouseLeave={cancelPress}
          onTouchStart={startPress}
          onTouchEnd={cancelPress}
          onTouchCancel={cancelPress}
          title="Hold to unlock protected vault"
        >
          <span className="text-xl font-bold tracking-tight text-zinc-800 dark:text-zinc-100">
            Notes
          </span>
          <span className="text-[10px] uppercase font-mono px-1.5 py-0.5 rounded bg-zinc-200 dark:bg-zinc-800 text-zinc-500">
            Cover
          </span>
        </div>
        <button
          onClick={onUnlockRequested}
          className="text-xs text-zinc-400 hover:text-zinc-600 dark:hover:text-zinc-300 underline"
          title="Unlock vault"
        >
          Unlock
        </button>
      </header>

      <div className="flex-1 overflow-y-auto px-5 py-4 flex flex-col gap-4">
        <div>
          <h2 className="text-2xl font-bold tracking-tight text-zinc-900 dark:text-zinc-100">
            Today
          </h2>
          <p className="text-sm text-zinc-500 dark:text-zinc-400 mt-0.5">
            {items.length === 0
              ? 'Keep a short list for the day.'
              : `${remaining} remaining · ${items.length} total`}
          </p>
        </div>

        <form
          onSubmit={add}
          className="flex items-center gap-2 p-2 rounded-xl bg-white dark:bg-zinc-900 border border-zinc-200 dark:border-zinc-800 shadow-sm"
        >
          <input
            data-testid="todo-input"
            type="text"
            value={input}
            onChange={(e) => setInput(e.target.value)}
            placeholder="Add a task"
            className="flex-1 px-3 py-1.5 bg-transparent text-sm focus:outline-none text-zinc-900 dark:text-zinc-100 placeholder-zinc-400"
          />
          <button
            type="submit"
            data-testid="todo-add"
            className="p-2 rounded-lg bg-[#315e63] dark:bg-[#78aeb3] text-white dark:text-zinc-950 hover:opacity-90 transition-opacity"
            aria-label="Add task"
          >
            <Plus className="w-4 h-4" />
          </button>
        </form>

        <div className="flex-1 space-y-2">
          {items.length === 0 ? (
            <div className="py-12 text-center text-sm text-zinc-400">No tasks yet</div>
          ) : (
            items.map((item) => (
              <div
                key={item.id}
                className="flex items-center justify-between p-3 rounded-xl bg-white dark:bg-zinc-900/70 border border-zinc-200/80 dark:border-zinc-800/80 transition-all hover:border-zinc-300"
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
                  aria-label="Delete task"
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
