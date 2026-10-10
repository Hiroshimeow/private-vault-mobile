import React, { useState, useRef, useEffect } from 'react';
import { ChevronLeft, ChevronRight, Plus, Circle } from 'lucide-react';

interface CalendarCoverProps {
  onUnlockRequested: () => void;
}

export const CalendarCover: React.FC<CalendarCoverProps> = ({ onUnlockRequested }) => {
  const [currentDate, setCurrentDate] = useState(new Date());
  const [selectedDay, setSelectedDay] = useState(new Date().getDate());
  const [events, setEvents] = useState<{ [day: number]: string[] }>({
    [new Date().getDate()]: ['Họp nhóm dự án 10:00', 'Xem lại báo cáo tài chính'],
    [(new Date().getDate() + 2) % 28 || 1]: ['Hẹn ăn tối đối tác'],
  });
  const [newEventText, setNewEventText] = useState('');

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

  const handleAddEvent = (e: React.FormEvent) => {
    e.preventDefault();
    if (!newEventText.trim()) return;
    const currentList = events[selectedDay] || [];
    setEvents({ ...events, [selectedDay]: [...currentList, newEventText.trim()] });
    setNewEventText('');
  };

  const daysInMonth = 31;
  const days = Array.from({ length: daysInMonth }, (_, i) => i + 1);

  return (
    <div className="flex flex-col h-full max-w-md mx-auto bg-zinc-50 dark:bg-[#101718] select-none font-sans">
      <header className="px-5 py-4 border-b border-zinc-200/80 dark:border-zinc-800/80 flex items-center justify-between">
        <div
          onMouseDown={startPress}
          onMouseUp={cancelPress}
          onMouseLeave={cancelPress}
          onTouchStart={startPress}
          onTouchEnd={cancelPress}
          className={`cursor-pointer transition-all flex items-center gap-2 ${
            isPressing ? 'opacity-50 scale-95' : 'opacity-100'
          }`}
          title="Nhấn giữ để mở Thư mục Bảo mật"
        >
          <span className="text-xl font-bold tracking-tight text-zinc-800 dark:text-zinc-100">
            Lịch nhắc
          </span>
          <span className="text-[10px] uppercase font-mono px-1.5 py-0.5 rounded bg-zinc-200 dark:bg-zinc-800 text-zinc-500">
            Cover
          </span>
        </div>
        <button
          onClick={onUnlockRequested}
          className="text-xs text-zinc-400 hover:text-zinc-600 dark:hover:text-zinc-300 underline"
        >
          Mở khóa
        </button>
      </header>

      <div className="flex-1 overflow-y-auto p-4 space-y-4">
        {/* Month selector */}
        <div className="flex items-center justify-between px-2">
          <h2 className="text-base font-bold text-zinc-900 dark:text-zinc-100">
            Tháng {currentDate.getMonth() + 1}, {currentDate.getFullYear()}
          </h2>
          <div className="flex items-center gap-1">
            <button
              onClick={() => setCurrentDate(new Date(currentDate.setMonth(currentDate.getMonth() - 1)))}
              className="p-1 rounded-lg hover:bg-zinc-200 dark:hover:bg-zinc-800"
            >
              <ChevronLeft className="w-4 h-4" />
            </button>
            <button
              onClick={() => setCurrentDate(new Date(currentDate.setMonth(currentDate.getMonth() + 1)))}
              className="p-1 rounded-lg hover:bg-zinc-200 dark:hover:bg-zinc-800"
            >
              <ChevronRight className="w-4 h-4" />
            </button>
          </div>
        </div>

        {/* Days grid */}
        <div className="grid grid-cols-7 gap-1.5 text-center text-xs">
          {['T2', 'T3', 'T4', 'T5', 'T6', 'T7', 'CN'].map((d) => (
            <div key={d} className="font-semibold text-zinc-400 py-1">
              {d}
            </div>
          ))}
          {days.map((day) => {
            const hasEv = !!events[day]?.length;
            const isSel = day === selectedDay;
            return (
              <button
                key={day}
                onClick={() => setSelectedDay(day)}
                className={`py-2 rounded-xl flex flex-col items-center justify-center relative transition-all ${
                  isSel
                    ? 'bg-[#315e63] dark:bg-[#78aeb3] text-white dark:text-zinc-950 font-bold shadow-xs'
                    : 'text-zinc-700 dark:text-zinc-300 hover:bg-zinc-100 dark:hover:bg-zinc-800'
                }`}
              >
                <span>{day}</span>
                {hasEv && (
                  <span
                    className={`w-1 h-1 rounded-full mt-0.5 ${
                      isSel ? 'bg-white dark:bg-zinc-950' : 'bg-teal-500'
                    }`}
                  />
                )}
              </button>
            );
          })}
        </div>

        {/* Selected day events */}
        <div className="pt-2 border-t border-zinc-200 dark:border-zinc-800 space-y-3">
          <div className="flex items-center justify-between text-xs font-semibold text-zinc-700 dark:text-zinc-300">
            <span>Sự kiện ngày {selectedDay}</span>
            <span className="text-zinc-400 text-[11px] font-mono">
              {events[selectedDay]?.length || 0} mục
            </span>
          </div>

          <form onSubmit={handleAddEvent} className="flex gap-2">
            <input
              type="text"
              value={newEventText}
              onChange={(e) => setNewEventText(e.target.value)}
              placeholder="Thêm lời nhắc cho ngày này..."
              className="flex-1 px-3 py-1.5 rounded-xl border border-zinc-200 dark:border-zinc-700 bg-white dark:bg-zinc-900 text-xs text-zinc-900 dark:text-zinc-100 focus:outline-none"
            />
            <button
              type="submit"
              className="p-2 rounded-xl bg-[#315e63] dark:bg-[#78aeb3] text-white dark:text-zinc-950"
            >
              <Plus className="w-4 h-4" />
            </button>
          </form>

          <div className="space-y-1.5">
            {(events[selectedDay] || []).map((ev, i) => (
              <div
                key={i}
                className="p-2.5 rounded-xl bg-white dark:bg-zinc-900/80 border border-zinc-200/80 dark:border-zinc-800 flex items-center gap-2.5 text-xs text-zinc-800 dark:text-zinc-200"
              >
                <Circle className="w-3.5 h-3.5 text-teal-500 shrink-0" />
                <span className="flex-1">{ev}</span>
              </div>
            ))}
          </div>
        </div>
      </div>
    </div>
  );
};
