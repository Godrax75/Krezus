export interface User {
  id: string;
  firstName: string;
  email: string;
  avatarUrl?: string;
  activationDate: string;
  giftedBy?: string;
}

export interface Stock {
  id: string;
  ticker: string;
  name: string;
  logoUrl: string;
  sector: string;
  exchange: string;
  description: string;
  currentPrice: number;
  previousClose: number;
  dayChange: number;
  dayChangePercent: number;
  high52w: number;
  low52w: number;
}

export interface Position {
  stockId: string;
  shares: number;
  averageCost: number;
  acquisitionDate: string;
  currentValue: number;
  totalGain: number;
  totalGainPercent: number;
}

export interface Portfolio {
  totalValue: number;
  totalGain: number;
  totalGainPercent: number;
  positions: Position[];
}

export interface ActivityEvent {
  id: string;
  type: 'activation' | 'dividend' | 'news' | 'milestone';
  title: string;
  description: string;
  date: string;
  icon: string;
  color: string;
}

export interface Notification {
  id: string;
  type: 'price_move' | 'dividend' | 'news' | 'education' | 'anniversary';
  title: string;
  description: string;
  date: string;
  read: boolean;
}

export interface EducationModule {
  id: string;
  title: string;
  duration: string;
  status: 'locked' | 'available' | 'completed';
  content: string;
  quiz: QuizQuestion[];
}

export interface QuizQuestion {
  id: string;
  question: string;
  options: string[];
  correctIndex: number;
}

export interface NewsArticle {
  id: string;
  title: string;
  source: string;
  date: string;
  imageUrl: string;
  url: string;
}

export interface ChartDataPoint {
  timestamp: number;
  value: number;
}

export type TimePeriod = '1J' | '1S' | '1M' | '3M' | '6M' | '1A' | 'Max';

export interface GiftReveal {
  stocks: { ticker: string; name: string; logoUrl: string; shares: number }[];
  initialValue: number;
  personalMessage?: string;
  giftedBy?: string;
}
