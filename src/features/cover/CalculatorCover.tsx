import React, { useState, useRef, useEffect } from 'react';

interface CalculatorCoverProps {
  onUnlockRequested: () => void;
}

type CalculatorKeyRole = 'number' | 'operator' | 'destructive' | 'equals';

export const CalculatorCover: React.FC<CalculatorCoverProps> = ({ onUnlockRequested }) => {
  const [display, setDisplay] = useState('0');
  const [left, setLeft] = useState<number | null>(null);
  const [operator, setOperator] = useState<string | null>(null);
  const [replace, setReplace] = useState(true);

  const headerTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const equalsTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const [isHeaderPressing, setIsHeaderPressing] = useState(false);

  const startHeaderPress = (e: React.PointerEvent) => {
    e.preventDefault();
    setIsHeaderPressing(true);
    if (headerTimerRef.current) clearTimeout(headerTimerRef.current);
    headerTimerRef.current = setTimeout(() => {
      setIsHeaderPressing(false);
      onUnlockRequested();
    }, 750);
  };

  const cancelHeaderPress = () => {
    setIsHeaderPressing(false);
    if (headerTimerRef.current) {
      clearTimeout(headerTimerRef.current);
      headerTimerRef.current = null;
    }
  };

  const startEqualsPress = (e: React.PointerEvent) => {
    e.preventDefault();
    if (equalsTimerRef.current) clearTimeout(equalsTimerRef.current);
    equalsTimerRef.current = setTimeout(() => {
      onUnlockRequested();
    }, 750);
  };

  const cancelEqualsPress = () => {
    if (equalsTimerRef.current) {
      clearTimeout(equalsTimerRef.current);
      equalsTimerRef.current = null;
    }
  };

  useEffect(() => {
    return () => {
      if (headerTimerRef.current) clearTimeout(headerTimerRef.current);
      if (equalsTimerRef.current) clearTimeout(equalsTimerRef.current);
    };
  }, []);

  const format = (value: number): string => {
    if (Number.isNaN(value) || !Number.isFinite(value)) return 'Error';
    if (Math.round(value) === value) return value.toString();
    const text = value.toFixed(8);
    return text.replace(/0+$/, '').replace(/\.$/, '');
  };

  const applyPending = (leftVal: number | null, op: string | null, currentDisplay: string): string => {
    if (leftVal === null || op === null) return currentDisplay;
    const right = parseFloat(currentDisplay);
    if (Number.isNaN(right)) return currentDisplay;

    let res = right;
    switch (op) {
      case '+':
        res = leftVal + right;
        break;
      case '-':
        res = leftVal - right;
        break;
      case '×':
        res = leftVal * right;
        break;
      case '÷':
        res = right === 0 ? NaN : leftVal / right;
        break;
    }
    return format(res);
  };

  const digit = (d: string) => {
    if (replace || display === '0') {
      setDisplay(d);
      setReplace(false);
    } else if (display.length < 14) {
      setDisplay(display + d);
    }
  };

  const operation = (op: string) => {
    if (operator && replace) {
      // Switch operator without re-calculating
      setOperator(op);
      return;
    }
    const calculated = applyPending(left, operator, display);
    setDisplay(calculated);
    setLeft(parseFloat(calculated));
    setOperator(op);
    setReplace(true);
  };

  const equals = () => {
    const calculated = applyPending(left, operator, display);
    setDisplay(calculated);
    setOperator(null);
    setLeft(null);
    setReplace(true);
  };

  const clear = () => {
    setDisplay('0');
    setLeft(null);
    setOperator(null);
    setReplace(true);
  };

  const press = (label: string) => {
    if (/^\d$/.test(label)) {
      digit(label);
    } else if (label === 'C') {
      clear();
    } else if (label === '=') {
      equals();
    } else {
      operation(label);
    }
  };

  const roleFor = (label: string): CalculatorKeyRole => {
    if (label === 'C') return 'destructive';
    if (label === '=') return 'equals';
    if ('0123456789'.includes(label)) return 'number';
    return 'operator';
  };

  const buttonStyle = (role: CalculatorKeyRole): string => {
    switch (role) {
      case 'number':
        return 'bg-zinc-200 dark:bg-zinc-800 text-zinc-900 dark:text-zinc-100 hover:bg-zinc-300 dark:hover:bg-zinc-700 active:scale-95';
      case 'operator':
        return 'bg-teal-100 dark:bg-teal-900/60 text-teal-900 dark:text-teal-100 hover:bg-teal-200 dark:hover:bg-teal-800/80 active:scale-95';
      case 'destructive':
        return 'bg-rose-100 dark:bg-rose-950/60 text-rose-800 dark:text-rose-200 hover:bg-rose-200 dark:hover:bg-rose-900/80 active:scale-95';
      case 'equals':
        return 'bg-[#315e63] dark:bg-[#78aeb3] text-white dark:text-zinc-950 font-bold hover:opacity-90 active:scale-95';
    }
  };

  const keys = [
    '7', '8', '9', '÷',
    '4', '5', '6', '×',
    '1', '2', '3', '-',
    'C', '0', '=', '+',
  ];

  return (
    <div className="flex flex-col h-full w-full bg-zinc-50 dark:bg-[#101718] select-none">
      {/* Cover Header without revealing labels */}
      <header className="px-5 py-4 pt-[max(1rem,env(safe-area-inset-top))] border-b border-zinc-200/80 dark:border-zinc-800/80 flex items-center justify-between shrink-0">
        <div
          data-testid="cover-title"
          className={`cursor-pointer transition-opacity duration-200 select-none flex items-center ${
            isHeaderPressing ? 'opacity-60 scale-95' : 'opacity-100'
          }`}
          onPointerDown={startHeaderPress}
          onPointerUp={cancelHeaderPress}
          onPointerCancel={cancelHeaderPress}
          onPointerLeave={cancelHeaderPress}
        >
          <span className="text-xl font-bold tracking-tight text-zinc-800 dark:text-zinc-100">
            Calculator
          </span>
        </div>
      </header>

      {/* Screen / Display Area */}
      <div className="flex-1 flex flex-col justify-end px-6 py-6 overflow-hidden">
        <div className="text-right text-sm text-zinc-400 mb-1 h-5 font-mono">
          {left !== null && operator ? `${left} ${operator}` : ''}
        </div>
        <div
          data-testid="calculator-display"
          className="text-right text-5xl md:text-6xl font-light tracking-tight font-mono overflow-x-auto whitespace-nowrap text-zinc-900 dark:text-zinc-50"
        >
          {display}
        </div>
      </div>

      {/* Responsive Fullscreen Keypad Grid */}
      <div className="p-4 pb-[max(1.5rem,env(safe-area-inset-bottom))] grid grid-cols-4 grid-rows-4 gap-3 h-[52%] shrink-0">
        {keys.map((key) => {
          const role = roleFor(key);
          const isEquals = key === '=';
          return (
            <button
              key={key}
              type="button"
              data-testid={`calculator-key-${key}`}
              onClick={() => press(key)}
              onPointerDown={isEquals ? startEqualsPress : undefined}
              onPointerUp={isEquals ? cancelEqualsPress : undefined}
              onPointerCancel={isEquals ? cancelEqualsPress : undefined}
              onPointerLeave={isEquals ? cancelEqualsPress : undefined}
              className={`h-full min-h-[56px] rounded-2xl text-2xl font-medium transition-all shadow-xs flex items-center justify-center ${buttonStyle(
                role
              )}`}
            >
              {key}
            </button>
          );
        })}
      </div>
    </div>
  );
};
