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

  // Calculator unlock gate: holding '=' triggers unlock request directly
  const equalsTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  const startEqualsPress = () => {
    equalsTimerRef.current = setTimeout(() => {
      onUnlockRequested();
    }, 650);
  };

  const cancelEqualsPress = () => {
    if (equalsTimerRef.current) {
      clearTimeout(equalsTimerRef.current);
      equalsTimerRef.current = null;
    }
  };

  const keys = [
    '7', '8', '9', '÷',
    '4', '5', '6', '×',
    '1', '2', '3', '-',
    'C', '0', '=', '+',
  ];

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
            Calculator
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

      <div className="flex-1 flex flex-col justify-end px-6 py-6 overflow-hidden">
        <div className="text-right text-xs text-zinc-400 mb-1 h-4 font-mono">
          {left !== null && operator ? `${left} ${operator}` : ''}
        </div>
        <div
          data-testid="calculator-display"
          className="text-right text-5xl font-light tracking-tight font-mono overflow-x-auto whitespace-nowrap text-zinc-900 dark:text-zinc-50"
        >
          {display}
        </div>
      </div>

      <div className="p-4 pb-8 grid grid-cols-4 gap-3">
        {keys.map((key) => {
          const role = roleFor(key);
          return (
            <button
              key={key}
              data-testid={`calculator-key-${key}`}
              onClick={() => press(key)}
              onMouseDown={key === '=' ? startEqualsPress : undefined}
              onMouseUp={key === '=' ? cancelEqualsPress : undefined}
              onMouseLeave={key === '=' ? cancelEqualsPress : undefined}
              onTouchStart={key === '=' ? startEqualsPress : undefined}
              onTouchEnd={key === '=' ? cancelEqualsPress : undefined}
              onTouchCancel={key === '=' ? cancelEqualsPress : undefined}
              className={`h-16 rounded-2xl text-2xl font-medium transition-all shadow-sm flex items-center justify-center ${buttonStyle(
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
