import { LocalVaultRepository } from '../vault/vaultRepository';

// Programmatic high-definition SVGs converted to PNG/JPEG data blobs for sample vault media
export const createSampleSvgImage = (
  type: 'document' | 'travel' | 'finance' | 'family' | 'passcode'
): Uint8Array => {
  let svg = '';
  switch (type) {
    case 'travel':
      svg = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1200 900" width="1200" height="900">
        <defs>
          <linearGradient id="sky" x1="0" y1="0" x2="0" y2="1">
            <stop offset="0%" stop-color="#0f2027" />
            <stop offset="50%" stop-color="#203a43" />
            <stop offset="100%" stop-color="#2c5364" />
          </linearGradient>
          <linearGradient id="sun" x1="0" y1="0" x2="1" y2="1">
            <stop offset="0%" stop-color="#ff9966" />
            <stop offset="100%" stop-color="#ff5e62" />
          </linearGradient>
          <linearGradient id="ocean" x1="0" y1="0" x2="0" y2="1">
            <stop offset="0%" stop-color="#1488cc" />
            <stop offset="100%" stop-color="#2b32b2" />
          </linearGradient>
        </defs>
        <rect width="1200" height="900" fill="url(#sky)" />
        <circle cx="600" cy="450" r="140" fill="url(#sun)" opacity="0.9" />
        <path d="M0 500 Q 300 480 600 500 T 1200 500 L 1200 900 L 0 900 Z" fill="url(#ocean)" />
        <polygon points="100,500 250,340 400,500" fill="#1b2a4a" opacity="0.8" />
        <polygon points="320,500 480,310 650,500" fill="#121b2f" />
        <polygon points="580,500 780,260 950,500" fill="#1b2a4a" opacity="0.9" />
        <polygon points="850,500 1020,330 1180,500" fill="#121b2f" />
        <text x="60" y="820" fill="#ffffff" font-family="system-ui, sans-serif" font-size="34" font-weight="700">Da Nang Coastline · Sunset 2026</text>
        <text x="60" y="860" fill="#88bbee" font-family="monospace" font-size="18">SECURE VAULT CAPTURE · EXIF ENCRYPTED</text>
      </svg>`;
      break;

    case 'finance':
      svg = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1200 900" width="1200" height="900">
        <defs>
          <linearGradient id="finbg" x1="0" y1="0" x2="1" y2="1">
            <stop offset="0%" stop-color="#09101d" />
            <stop offset="100%" stop-color="#111c2e" />
          </linearGradient>
          <linearGradient id="neonGreen" x1="0" y1="0" x2="0" y2="1">
            <stop offset="0%" stop-color="#10b981" />
            <stop offset="100%" stop-color="#059669" />
          </linearGradient>
        </defs>
        <rect width="1200" height="900" fill="url(#finbg)" />
        <g stroke="#1e293b" stroke-width="1">
          <line x1="100" y1="150" x2="1100" y2="150" />
          <line x1="100" y1="300" x2="1100" y2="300" />
          <line x1="100" y1="450" x2="1100" y2="450" />
          <line x1="100" y1="600" x2="1100" y2="600" />
        </g>
        <path d="M 120 620 L 250 540 L 380 580 L 520 420 L 660 460 L 800 280 L 940 310 L 1080 180" fill="none" stroke="#10b981" stroke-width="6" stroke-linecap="round" />
        <path d="M 120 620 L 250 540 L 380 580 L 520 420 L 660 460 L 800 280 L 940 310 L 1080 180 L 1080 750 L 120 750 Z" fill="url(#neonGreen)" opacity="0.12" />
        <!-- Candlesticks -->
        <rect x="235" y="520" width="30" height="40" fill="#10b981" rx="4" />
        <rect x="365" y="550" width="30" height="60" fill="#ef4444" rx="4" />
        <rect x="505" y="400" width="30" height="50" fill="#10b981" rx="4" />
        <rect x="785" y="260" width="30" height="60" fill="#10b981" rx="4" />
        <rect x="925" y="290" width="30" height="40" fill="#ef4444" rx="4" />
        <text x="120" y="100" fill="#ffffff" font-family="system-ui, sans-serif" font-size="32" font-weight="700">Confidential Portfolio Summary: +284.5%</text>
        <text x="120" y="730" fill="#10b981" font-family="monospace" font-size="22" font-weight="600">Total Net Asset Value: $485,200 USD</text>
        <text x="120" y="770" fill="#64748b" font-family="monospace" font-size="16">RESTRICTED VIEW · STORED IN VAULT REPOSITORY ONLY</text>
      </svg>`;
      break;

    case 'document':
      svg = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1200 900" width="1200" height="900">
        <rect width="1200" height="900" fill="#1e1e24" />
        <rect x="250" y="60" width="700" height="780" rx="16" fill="#ffffff" filter="drop-shadow(0 10px 30px rgba(0,0,0,0.5))" />
        <text x="320" y="140" fill="#0f172a" font-family="system-ui, serif" font-size="28" font-weight="700">CONFIDENTIAL ACQUISITION AGREEMENT</text>
        <line x1="320" y1="165" x2="880" y2="165" stroke="#cbd5e1" stroke-width="2" />
        <rect x="320" y="200" width="460" height="14" fill="#94a3b8" rx="4" />
        <rect x="320" y="230" width="540" height="14" fill="#cbd5e1" rx="4" />
        <rect x="320" y="260" width="510" height="14" fill="#cbd5e1" rx="4" />
        <rect x="320" y="290" width="480" height="14" fill="#cbd5e1" rx="4" />
        <rect x="320" y="340" width="540" height="14" fill="#94a3b8" rx="4" />
        <rect x="320" y="370" width="520" height="14" fill="#cbd5e1" rx="4" />
        <rect x="320" y="400" width="490" height="14" fill="#cbd5e1" rx="4" />
        <!-- Red Stamp -->
        <g transform="translate(620, 520) rotate(-12)">
          <rect width="220" height="70" rx="8" fill="none" stroke="#dc2626" stroke-width="4" stroke-dasharray="8 4" />
          <text x="25" y="46" fill="#dc2626" font-family="system-ui, sans-serif" font-size="24" font-weight="900" letter-spacing="2">TOP SECRET</text>
        </g>
        <circle cx="400" cy="720" r="35" fill="#f1f5f9" stroke="#94a3b8" stroke-width="2" />
        <path d="M 385 720 L 396 732 L 418 708" stroke="#16a34a" stroke-width="4" fill="none" stroke-linecap="round" />
        <text x="450" y="726" fill="#0f172a" font-family="monospace" font-size="16" font-weight="600">Digitally Sealed with AES-GCM Key</text>
      </svg>`;
      break;

    case 'family':
      svg = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1200 900" width="1200" height="900">
        <defs>
          <linearGradient id="warm" x1="0" y1="0" x2="1" y2="1">
            <stop offset="0%" stop-color="#2d132c" />
            <stop offset="50%" stop-color="#801336" />
            <stop offset="100%" stop-color="#ee4540" />
          </linearGradient>
        </defs>
        <rect width="1200" height="900" fill="url(#warm)" />
        <circle cx="300" cy="250" r="180" fill="#ffb400" opacity="0.25" />
        <circle cx="850" cy="300" r="220" fill="#f85f73" opacity="0.3" />
        <circle cx="600" cy="650" r="260" fill="#fbe3b5" opacity="0.2" />
        <text x="100" y="780" fill="#ffffff" font-family="system-ui, sans-serif" font-size="38" font-weight="800">Ky niem gia dinh · Da Lat 2026</text>
        <text x="100" y="830" fill="#fbe3b5" font-family="system-ui, sans-serif" font-size="20">Private family album · Protected memories</text>
      </svg>`;
      break;

    case 'passcode':
    default:
      svg = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1200 900" width="1200" height="900">
        <rect width="1200" height="900" fill="#0b1320" />
        <rect x="200" y="150" width="800" height="600" rx="24" fill="#131e32" stroke="#253553" stroke-width="3" />
        <circle cx="600" cy="300" r="60" fill="#1b2a47" stroke="#38bdf8" stroke-width="4" />
        <path d="M 585 300 L 615 300 M 600 285 L 600 315" stroke="#38bdf8" stroke-width="4" stroke-linecap="round" />
        <text x="600" y="440" fill="#ffffff" font-family="system-ui, sans-serif" font-size="30" font-weight="700" text-anchor="middle">Seed Phrase & Recovery Keys</text>
        <text x="600" y="490" fill="#94a3b8" font-family="monospace" font-size="18" text-anchor="middle">24 words encrypted offline · Never synced to cloud</text>
        <rect x="300" y="550" width="600" height="70" rx="14" fill="#0f172a" stroke="#334155" />
        <text x="600" y="594" fill="#38bdf8" font-family="monospace" font-size="20" text-anchor="middle">•••• •••• •••• •••• •••• ••••</text>
      </svg>`;
      break;
  }

  return new TextEncoder().encode(svg);
};

export const seedSampleVaultMedia = async (repository: LocalVaultRepository): Promise<void> => {
  const samples = [
    {
      name: 'Ky_Niem_Da_Nang_Sunset.svg',
      type: 'travel' as const,
      album: 'Du lịch',
      isFavorite: true,
      width: 1200,
      height: 900,
    },
    {
      name: 'Bao_Cao_Tai_Chinh_Q1_2026.svg',
      type: 'finance' as const,
      album: 'Tài chính',
      isFavorite: true,
      width: 1200,
      height: 900,
    },
    {
      name: 'Hop_Dong_Mua_Ban_Bao_Mat.svg',
      type: 'document' as const,
      album: 'Hợp đồng',
      isFavorite: false,
      width: 1200,
      height: 900,
    },
    {
      name: 'Ky_Niem_Gia_Dinh_Da_Lat.svg',
      type: 'family' as const,
      album: 'Gia đình',
      isFavorite: true,
      width: 1200,
      height: 900,
    },
    {
      name: 'Vi_Dien_Tu_Recovery_Seed.svg',
      type: 'passcode' as const,
      album: 'Bí mật',
      isFavorite: true,
      width: 1200,
      height: 900,
    },
  ];

  for (const s of samples) {
    const bytes = createSampleSvgImage(s.type);
    await repository.addBytes(bytes, {
      kind: 'image',
      name: s.name,
      album: s.album,
      isFavorite: s.isFavorite,
      width: s.width,
      height: s.height,
    });
  }
};
