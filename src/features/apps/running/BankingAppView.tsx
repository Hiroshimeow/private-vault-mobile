import React, { useState } from 'react';
import {
  ChevronLeft,
  Eye,
  EyeOff,
  Send,
  QrCode,
  ArrowUpRight,
  ArrowDownLeft,
  CreditCard,
  Shield,
  CheckCircle2,
} from 'lucide-react';

interface BankingAppViewProps {
  appName: string;
  onBack: () => void;
}

export const BankingAppView: React.FC<BankingAppViewProps> = ({ appName, onBack }) => {
  const [showBalance, setShowBalance] = useState(false);
  const [balance, setBalance] = useState(258450000);
  const [isTransferModalOpen, setIsTransferModalOpen] = useState(false);
  const [recipient, setRecipient] = useState('');
  const [amount, setAmount] = useState('');
  const [toast, setToast] = useState<string | null>(null);

  const [transactions, setTransactions] = useState([
    {
      id: 'tx-1',
      title: 'Nhận tiền từ Cty Cổ phần Công nghệ',
      amount: '+50,000,000 VND',
      time: 'Hôm nay, 10:30',
      type: 'in' as const,
    },
    {
      id: 'tx-2',
      title: 'Chuyển tiền đầu tư bảo mật',
      amount: '-15,200,000 VND',
      time: 'Hôm qua, 16:45',
      type: 'out' as const,
    },
    {
      id: 'tx-3',
      title: 'Thanh toán trực tuyến bảo mật',
      amount: '-2,450,000 VND',
      time: '08/10/2026',
      type: 'out' as const,
    },
  ]);

  const handleTransfer = (e: React.FormEvent) => {
    e.preventDefault();
    const val = parseInt(amount.replace(/\D/g, ''), 10);
    if (!val || !recipient.trim()) return;

    setBalance((b) => b - val);
    const newTx = {
      id: `tx-${Date.now()}`,
      title: `Chuyển tới: ${recipient}`,
      amount: `-${val.toLocaleString()} VND`,
      time: 'Vừa xong',
      type: 'out' as const,
    };
    setTransactions([newTx, ...transactions]);
    setIsTransferModalOpen(false);
    setRecipient('');
    setAmount('');
    setToast('Giao dịch chuyển khoản bảo mật thành công');
    setTimeout(() => setToast(null), 3000);
  };

  return (
    <div className="flex flex-col h-full bg-[#f4f7f6] dark:bg-[#0c1212] text-zinc-900 dark:text-zinc-100 select-none overflow-hidden font-sans">
      {/* Header */}
      <div className="bg-[#005a3c] text-white px-3.5 py-3.5 flex items-center justify-between shadow-md shrink-0">
        <div className="flex items-center gap-2.5">
          <button onClick={onBack} className="p-1 rounded-full hover:bg-white/20">
            <ChevronLeft className="w-5 h-5" />
          </button>
          <div>
            <div className="flex items-center gap-1.5">
              <h3 className="text-sm font-bold">{appName || 'VCB Digibank'}</h3>
              <span className="text-[10px] px-1.5 py-0.2 rounded bg-white/20 font-mono">
                Isolated UID
              </span>
            </div>
            <p className="text-[10px] text-white/80">Môi trường giao dịch cách ly an toàn</p>
          </div>
        </div>

        <div className="flex items-center gap-1 text-xs">
          <Shield className="w-4 h-4 text-emerald-300" />
          <span className="text-[10px] text-emerald-200">Smart OTP</span>
        </div>
      </div>

      <div className="flex-1 overflow-y-auto p-4 space-y-4">
        {/* Balance Card */}
        <div className="p-4 rounded-3xl bg-gradient-to-br from-[#005a3c] to-[#013f2a] text-white shadow-xl space-y-3">
          <div className="flex items-center justify-between text-xs text-emerald-200">
            <span>Tài khoản thanh toán bảo mật</span>
            <button
              onClick={() => setShowBalance(!showBalance)}
              className="p-1 hover:text-white flex items-center gap-1"
            >
              {showBalance ? <EyeOff className="w-4 h-4" /> : <Eye className="w-4 h-4" />}
            </button>
          </div>

          <div>
            <span className="text-xl font-bold font-mono tracking-tight">
              {showBalance ? `${balance.toLocaleString()} VND` : '•••••••••••• VND'}
            </span>
          </div>

          <div className="flex items-center justify-between text-[11px] text-emerald-200/80 font-mono pt-1 border-t border-emerald-700/50">
            <span>STK: 1029 8849 2011</span>
            <span>Hạn mức: Vô hạn</span>
          </div>
        </div>

        {/* Action Buttons */}
        <div className="grid grid-cols-4 gap-2">
          <button
            onClick={() => setIsTransferModalOpen(true)}
            className="p-3 rounded-2xl bg-white dark:bg-[#151f1f] border border-zinc-200/80 dark:border-zinc-800 flex flex-col items-center gap-1.5 hover:border-emerald-500 shadow-xs active:scale-95 transition-all"
          >
            <div className="w-8 h-8 rounded-full bg-emerald-500/10 text-emerald-600 flex items-center justify-center">
              <Send className="w-4 h-4" />
            </div>
            <span className="text-[10px] font-bold">Chuyển tiền</span>
          </button>

          <button
            onClick={() => {
              setToast('Mã QR cá nhân an toàn đã tạo');
              setTimeout(() => setToast(null), 2500);
            }}
            className="p-3 rounded-2xl bg-white dark:bg-[#151f1f] border border-zinc-200/80 dark:border-zinc-800 flex flex-col items-center gap-1.5 hover:border-emerald-500 shadow-xs active:scale-95 transition-all"
          >
            <div className="w-8 h-8 rounded-full bg-emerald-500/10 text-emerald-600 flex items-center justify-center">
              <QrCode className="w-4 h-4" />
            </div>
            <span className="text-[10px] font-bold">Quét QR</span>
          </button>

          <button
            onClick={() => {
              setBalance((b) => b + 10000000);
              setToast('Đã nạp 10,000,000 VND vào tài khoản');
              setTimeout(() => setToast(null), 2500);
            }}
            className="p-3 rounded-2xl bg-white dark:bg-[#151f1f] border border-zinc-200/80 dark:border-zinc-800 flex flex-col items-center gap-1.5 hover:border-emerald-500 shadow-xs active:scale-95 transition-all"
          >
            <div className="w-8 h-8 rounded-full bg-emerald-500/10 text-emerald-600 flex items-center justify-center">
              <ArrowDownLeft className="w-4 h-4" />
            </div>
            <span className="text-[10px] font-bold">Nạp tiền</span>
          </button>

          <button
            className="p-3 rounded-2xl bg-white dark:bg-[#151f1f] border border-zinc-200/80 dark:border-zinc-800 flex flex-col items-center gap-1.5 hover:border-emerald-500 shadow-xs active:scale-95 transition-all"
          >
            <div className="w-8 h-8 rounded-full bg-emerald-500/10 text-emerald-600 flex items-center justify-center">
              <CreditCard className="w-4 h-4" />
            </div>
            <span className="text-[10px] font-bold">Thẻ bí mật</span>
          </button>
        </div>

        {/* Transactions list */}
        <div className="space-y-2">
          <h4 className="text-xs font-bold uppercase tracking-wider text-zinc-500">
            Lịch sử giao dịch gần đây
          </h4>
          <div className="space-y-2">
            {transactions.map((tx) => (
              <div
                key={tx.id}
                className="p-3 rounded-2xl bg-white dark:bg-[#151f1f] border border-zinc-200/80 dark:border-zinc-800 flex items-center justify-between shadow-xs"
              >
                <div className="flex items-center gap-2.5 min-w-0">
                  <div
                    className={`w-8 h-8 rounded-full flex items-center justify-center shrink-0 ${
                      tx.type === 'in' ? 'bg-emerald-500/10 text-emerald-500' : 'bg-rose-500/10 text-rose-500'
                    }`}
                  >
                    {tx.type === 'in' ? (
                      <ArrowDownLeft className="w-4 h-4" />
                    ) : (
                      <ArrowUpRight className="w-4 h-4" />
                    )}
                  </div>
                  <div className="min-w-0">
                    <p className="text-xs font-semibold truncate max-w-[170px]">{tx.title}</p>
                    <p className="text-[10px] text-zinc-400 mt-0.5">{tx.time}</p>
                  </div>
                </div>
                <span
                  className={`text-xs font-bold font-mono ${
                    tx.type === 'in' ? 'text-emerald-500' : 'text-zinc-900 dark:text-zinc-100'
                  }`}
                >
                  {tx.amount}
                </span>
              </div>
            ))}
          </div>
        </div>
      </div>

      {/* Transfer Modal */}
      {isTransferModalOpen && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/60 backdrop-blur-xs p-4">
          <div className="w-full max-w-sm bg-white dark:bg-[#151f1f] rounded-3xl p-5 shadow-2xl border border-zinc-200 dark:border-zinc-800 space-y-4">
            <h3 className="text-sm font-bold">Chuyển tiền nhanh Smart OTP</h3>
            <form onSubmit={handleTransfer} className="space-y-3">
              <div>
                <label className="text-[11px] font-medium text-zinc-600 dark:text-zinc-400">
                  Số tài khoản / Người nhận
                </label>
                <input
                  type="text"
                  value={recipient}
                  onChange={(e) => setRecipient(e.target.value)}
                  placeholder="Nhập số tài khoản hoặc tên..."
                  className="w-full mt-1 p-2.5 rounded-xl border border-zinc-200 dark:border-zinc-700 bg-zinc-50 dark:bg-zinc-800 text-xs"
                  required
                />
              </div>
              <div>
                <label className="text-[11px] font-medium text-zinc-600 dark:text-zinc-400">
                  Số tiền (VND)
                </label>
                <input
                  type="number"
                  value={amount}
                  onChange={(e) => setAmount(e.target.value)}
                  placeholder="500000"
                  className="w-full mt-1 p-2.5 rounded-xl border border-zinc-200 dark:border-zinc-700 bg-zinc-50 dark:bg-zinc-800 text-xs font-mono"
                  required
                />
              </div>
              <div className="flex justify-end gap-2 pt-2">
                <button
                  type="button"
                  onClick={() => setIsTransferModalOpen(false)}
                  className="px-3.5 py-2 rounded-xl text-xs text-zinc-500 hover:bg-zinc-100"
                >
                  Hủy
                </button>
                <button
                  type="submit"
                  className="px-4 py-2 rounded-xl text-xs font-semibold bg-[#005a3c] text-white hover:opacity-90"
                >
                  Xác nhận chuyển
                </button>
              </div>
            </form>
          </div>
        </div>
      )}

      {toast && (
        <div className="p-3 bg-emerald-600 text-white font-bold text-xs flex items-center justify-center gap-1.5 shadow-lg">
          <CheckCircle2 className="w-4 h-4" />
          <span>{toast}</span>
        </div>
      )}
    </div>
  );
};
