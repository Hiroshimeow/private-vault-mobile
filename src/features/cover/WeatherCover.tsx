import React, { useState, useRef, useEffect } from 'react';
import { CloudSun, Sun, CloudRain, Wind, Droplets } from 'lucide-react';

interface WeatherCoverProps {
  onUnlockRequested: () => void;
}

export const WeatherCover: React.FC<WeatherCoverProps> = ({ onUnlockRequested }) => {
  const [city] = useState('Hà Nội');
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

  return (
    <div className="flex flex-col h-full max-w-md mx-auto bg-gradient-to-b from-sky-600 to-sky-900 text-white select-none font-sans">
      <header className="px-5 py-4 flex items-center justify-between border-b border-white/10">
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
          <span className="text-xl font-bold tracking-tight">Thời tiết</span>
          <span className="text-[10px] uppercase font-mono px-1.5 py-0.5 rounded bg-white/20 text-white">
            Cover
          </span>
        </div>
        <button
          onClick={onUnlockRequested}
          className="text-xs text-white/70 hover:text-white underline"
        >
          Mở khóa
        </button>
      </header>

      <div className="flex-1 overflow-y-auto p-6 flex flex-col items-center justify-between space-y-6">
        {/* City and Current Temp */}
        <div className="text-center space-y-1">
          <h2 className="text-2xl font-bold">{city}</h2>
          <p className="text-xs text-white/80">Có mây rải rác · Không khí tốt</p>
          <div className="flex items-center justify-center my-3">
            <CloudSun className="w-20 h-20 text-amber-300 drop-shadow-md" />
          </div>
          <div className="text-6xl font-light font-mono">29°C</div>
          <p className="text-xs text-white/70">Cao nhất: 32° · Thấp nhất: 24°</p>
        </div>

        {/* Hourly Forecast */}
        <div className="w-full p-4 rounded-3xl bg-white/10 backdrop-blur-md border border-white/15 space-y-2.5">
          <span className="text-[11px] font-semibold text-white/80 uppercase tracking-wider">
            Dự báo 24 giờ tới
          </span>
          <div className="flex justify-between text-center text-xs">
            <div>
              <p className="text-[10px] text-white/70">Bây giờ</p>
              <Sun className="w-5 h-5 mx-auto my-1 text-amber-300" />
              <p className="font-bold">29°</p>
            </div>
            <div>
              <p className="text-[10px] text-white/70">12:00</p>
              <CloudSun className="w-5 h-5 mx-auto my-1 text-amber-300" />
              <p className="font-bold">31°</p>
            </div>
            <div>
              <p className="text-[10px] text-white/70">15:00</p>
              <CloudSun className="w-5 h-5 mx-auto my-1 text-amber-300" />
              <p className="font-bold">30°</p>
            </div>
            <div>
              <p className="text-[10px] text-white/70">18:00</p>
              <CloudRain className="w-5 h-5 mx-auto my-1 text-sky-200" />
              <p className="font-bold">27°</p>
            </div>
            <div>
              <p className="text-[10px] text-white/70">21:00</p>
              <CloudSun className="w-5 h-5 mx-auto my-1 text-amber-200" />
              <p className="font-bold">25°</p>
            </div>
          </div>
        </div>

        {/* Metrics Grid */}
        <div className="w-full grid grid-cols-2 gap-3">
          <div className="p-3.5 rounded-2xl bg-white/10 backdrop-blur-md border border-white/15 flex items-center gap-3">
            <Droplets className="w-6 h-6 text-sky-200" />
            <div>
              <p className="text-[10px] text-white/70">Độ ẩm</p>
              <p className="text-sm font-bold font-mono">68%</p>
            </div>
          </div>
          <div className="p-3.5 rounded-2xl bg-white/10 backdrop-blur-md border border-white/15 flex items-center gap-3">
            <Wind className="w-6 h-6 text-sky-200" />
            <div>
              <p className="text-[10px] text-white/70">Gió</p>
              <p className="text-sm font-bold font-mono">14 km/h</p>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
};
