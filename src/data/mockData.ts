import { Stock, Position, ActivityEvent, Notification, EducationModule, NewsArticle, ChartDataPoint, GiftReveal } from '../types';

export const mockStocks: Record<string, Stock> = {
  AAPL: {
    id: 'aapl',
    ticker: 'AAPL',
    name: 'Apple Inc.',
    logoUrl: 'https://logo.clearbit.com/apple.com',
    sector: 'Technologie',
    exchange: 'NASDAQ',
    description: 'Apple conçoit, fabrique et commercialise des smartphones, ordinateurs, tablettes et accessoires. L\'entreprise propose également des services numériques comme l\'App Store, Apple Music et iCloud.',
    currentPrice: 198.45,
    previousClose: 195.20,
    dayChange: 3.25,
    dayChangePercent: 1.66,
    high52w: 210.30,
    low52w: 155.80,
  },
  MSFT: {
    id: 'msft',
    ticker: 'MSFT',
    name: 'Microsoft Corp.',
    logoUrl: 'https://logo.clearbit.com/microsoft.com',
    sector: 'Technologie',
    exchange: 'NASDAQ',
    description: 'Microsoft développe et supporte des logiciels, services, appareils et solutions. Ses produits phares incluent Windows, Office 365, Azure et Xbox.',
    currentPrice: 425.80,
    previousClose: 422.15,
    dayChange: 3.65,
    dayChangePercent: 0.86,
    high52w: 445.20,
    low52w: 360.50,
  },
  LVMH: {
    id: 'lvmh',
    ticker: 'MC.PA',
    name: 'LVMH Moët Hennessy',
    logoUrl: 'https://logo.clearbit.com/lvmh.com',
    sector: 'Luxe',
    exchange: 'Euronext Paris',
    description: 'LVMH est le leader mondial du luxe, regroupant des maisons prestigieuses comme Louis Vuitton, Dior, Moët & Chandon et Hennessy.',
    currentPrice: 745.20,
    previousClose: 752.10,
    dayChange: -6.90,
    dayChangePercent: -0.92,
    high52w: 890.00,
    low52w: 650.30,
  },
};

export const mockPositions: Position[] = [
  {
    stockId: 'aapl',
    shares: 2.5,
    averageCost: 178.30,
    acquisitionDate: '2026-02-14',
    currentValue: 496.13,
    totalGain: 50.38,
    totalGainPercent: 11.30,
  },
  {
    stockId: 'msft',
    shares: 1.0,
    averageCost: 395.00,
    acquisitionDate: '2026-02-14',
    currentValue: 425.80,
    totalGain: 30.80,
    totalGainPercent: 7.80,
  },
  {
    stockId: 'lvmh',
    shares: 0.5,
    averageCost: 720.00,
    acquisitionDate: '2026-02-14',
    currentValue: 372.60,
    totalGain: 12.60,
    totalGainPercent: 3.50,
  },
];

export const mockActivities: ActivityEvent[] = [
  {
    id: '1',
    type: 'activation',
    title: 'Coffret activé',
    description: 'Votre coffret cadeau Krezus a été activé avec succès',
    date: '2026-02-14',
    icon: 'gift',
    color: '#C9A84C',
  },
  {
    id: '2',
    type: 'dividend',
    title: 'Dividende reçu',
    description: 'Apple Inc. — +2,34 €',
    date: '2026-03-15',
    icon: 'trending-up',
    color: '#4CAF50',
  },
  {
    id: '3',
    type: 'news',
    title: 'Résultats trimestriels',
    description: 'Apple a publié ses résultats Q1 2026',
    date: '2026-04-01',
    icon: 'newspaper',
    color: '#2196F3',
  },
  {
    id: '4',
    type: 'milestone',
    title: '1 mois d\'investissement',
    description: 'Félicitations ! Votre portefeuille a 1 mois',
    date: '2026-03-14',
    icon: 'star',
    color: '#C9A84C',
  },
];

export const mockNotifications: Notification[] = [
  {
    id: '1',
    type: 'price_move',
    title: 'Apple en hausse de +5,2%',
    description: 'L\'action Apple a gagné 5,2% aujourd\'hui suite à l\'annonce de nouveaux produits.',
    date: '2026-04-02T14:30:00',
    read: false,
  },
  {
    id: '2',
    type: 'dividend',
    title: 'Dividende reçu : +2,34 €',
    description: 'Vous avez reçu un dividende de Apple Inc. sur votre portefeuille.',
    date: '2026-03-15T09:00:00',
    read: false,
  },
  {
    id: '3',
    type: 'education',
    title: 'Nouveau module disponible',
    description: 'Découvrez "Les dividendes expliqués" dans votre parcours éducatif.',
    date: '2026-03-10T10:00:00',
    read: true,
  },
  {
    id: '4',
    type: 'anniversary',
    title: '1 mois avec Krezus !',
    description: 'Ça fait déjà 1 mois que vous avez activé votre coffret. Bravo !',
    date: '2026-03-14T08:00:00',
    read: true,
  },
  {
    id: '5',
    type: 'news',
    title: 'Microsoft : acquisition majeure',
    description: 'Microsoft a annoncé l\'acquisition d\'une entreprise d\'IA pour 10 milliards $.',
    date: '2026-03-08T16:00:00',
    read: true,
  },
];

export const mockEducationModules: EducationModule[] = [
  {
    id: '1', title: "C'est quoi une action ?", duration: '3 min', status: 'completed',
    content: "Une action représente une part de propriété dans une entreprise. Quand vous possédez une action Apple, vous êtes littéralement copropriétaire d'Apple !\n\nLes entreprises émettent des actions pour lever des fonds et financer leur croissance. En échange, les actionnaires participent aux bénéfices (via les dividendes) et peuvent voter lors des assemblées générales.\n\nLe prix d'une action varie en fonction de l'offre et la demande sur le marché boursier. Si beaucoup d'investisseurs veulent acheter, le prix monte. Si beaucoup veulent vendre, le prix baisse.\n\nVotre coffret Krezus contient des fractions d'actions, ce qui signifie que vous possédez une partie d'une action complète. C'est une manière accessible d'investir dans de grandes entreprises.",
    quiz: [
      { id: 'q1', question: "Qu'est-ce qu'une action ?", options: ['Un prêt à une entreprise', 'Une part de propriété dans une entreprise', 'Un compte d\'épargne', 'Une assurance'], correctIndex: 1 },
      { id: 'q2', question: 'Que se passe-t-il quand beaucoup d\'investisseurs veulent acheter une action ?', options: ['Le prix baisse', 'Le prix reste stable', 'Le prix monte', 'L\'action est retirée du marché'], correctIndex: 2 },
    ],
  },
  {
    id: '2', title: 'Comprendre un graphique boursier', duration: '4 min', status: 'completed',
    content: "Les graphiques boursiers montrent l'évolution du prix d'une action dans le temps. L'axe horizontal représente le temps, et l'axe vertical représente le prix.\n\nLe graphique en courbe (line chart) est le plus simple : il relie les prix de clôture jour après jour. C'est celui que vous voyez dans l'app Krezus.\n\nLes périodes courtes (1 jour, 1 semaine) montrent les fluctuations quotidiennes. Les périodes longues (1 an, Max) montrent la tendance générale.\n\nConseil : ne paniquez pas face aux variations quotidiennes. Sur le long terme, les marchés ont historiquement tendance à monter.",
    quiz: [
      { id: 'q3', question: 'Que représente l\'axe vertical d\'un graphique boursier ?', options: ['Le temps', 'Le volume', 'Le prix', 'Le nombre d\'actionnaires'], correctIndex: 2 },
    ],
  },
  {
    id: '3', title: 'Les dividendes expliqués', duration: '3 min', status: 'completed',
    content: "Un dividende est une part des bénéfices qu'une entreprise distribue à ses actionnaires. C'est comme recevoir un loyer pour avoir investi dans l'entreprise.\n\nToutes les entreprises ne versent pas de dividendes. Certaines préfèrent réinvestir leurs bénéfices pour croître plus vite (comme beaucoup d'entreprises tech).\n\nLes dividendes sont généralement versés chaque trimestre (tous les 3 mois). Le montant dépend du nombre d'actions que vous possédez.\n\nDans votre app Krezus, vous recevrez une notification à chaque fois qu'un dividende est crédité sur votre portefeuille.",
    quiz: [
      { id: 'q4', question: "Qu'est-ce qu'un dividende ?", options: ['Une taxe sur les actions', 'Une part des bénéfices distribuée aux actionnaires', 'Le prix d\'entrée en bourse', 'Un frais de gestion'], correctIndex: 1 },
    ],
  },
  {
    id: '4', title: 'Pourquoi les cours montent et descendent', duration: '5 min', status: 'available',
    content: "Les prix des actions fluctuent constamment en raison de l'offre et de la demande. Plusieurs facteurs influencent ces mouvements.\n\nLes résultats financiers de l'entreprise sont le facteur principal. Si une entreprise publie de bons résultats, les investisseurs veulent acheter et le prix monte.\n\nL'environnement économique global joue aussi un rôle important : taux d'intérêt, inflation, géopolitique...\n\nLe sentiment du marché et la psychologie des investisseurs créent parfois des mouvements exagérés, à la hausse comme à la baisse.\n\nRetenir : sur le court terme, les prix sont imprévisibles. Sur le long terme, ils reflètent la valeur réelle de l'entreprise.",
    quiz: [
      { id: 'q5', question: 'Quel est le facteur principal qui influence le prix d\'une action ?', options: ['La météo', 'Les résultats financiers de l\'entreprise', 'L\'heure de la journée', 'Le nombre d\'employés'], correctIndex: 1 },
    ],
  },
  {
    id: '5', title: "Qu'est-ce qu'un indice boursier ?", duration: '3 min', status: 'available',
    content: "Un indice boursier est un panier d'actions qui représente un marché ou un secteur. Il sert de baromètre pour mesurer la santé du marché.\n\nLe CAC 40 regroupe les 40 plus grandes entreprises françaises cotées en bourse. Le S&P 500 regroupe les 500 plus grandes entreprises américaines.\n\nQuand on dit « la bourse monte », on parle généralement de ces indices.\n\nSuivre les indices vous aide à comprendre si votre portefeuille fait mieux ou moins bien que le marché dans son ensemble.",
    quiz: [
      { id: 'q6', question: 'Que représente le CAC 40 ?', options: ['40 actions au hasard', 'Les 40 plus grandes entreprises françaises cotées', 'Un fonds d\'investissement', 'Une taxe boursière'], correctIndex: 1 },
    ],
  },
  {
    id: '6', title: 'Diversifier son portefeuille', duration: '4 min', status: 'locked',
    content: "La diversification consiste à répartir ses investissements entre différentes entreprises, secteurs et zones géographiques.\n\nL'idée est simple : ne pas mettre tous ses œufs dans le même panier. Si une entreprise perd de la valeur, les autres peuvent compenser.\n\nVotre coffret Krezus est déjà diversifié avec des actions de différents secteurs !\n\nPlus vous diversifiez, plus vous réduisez le risque sans nécessairement réduire le potentiel de rendement.",
    quiz: [
      { id: 'q7', question: 'Pourquoi diversifier son portefeuille ?', options: ['Pour avoir plus d\'actions', 'Pour réduire le risque', 'Pour payer moins de frais', 'Pour impressionner ses amis'], correctIndex: 1 },
    ],
  },
  {
    id: '7', title: "Lire un rapport d'entreprise", duration: '5 min', status: 'locked',
    content: "Les entreprises cotées publient des rapports financiers chaque trimestre. Ces rapports contiennent des informations clés sur la santé de l'entreprise.\n\nLe chiffre d'affaires montre combien l'entreprise a vendu. Le bénéfice net montre combien elle a réellement gagné après toutes les dépenses.\n\nLe BPA (Bénéfice Par Action) est particulièrement important : il montre combien chaque action a généré de profit.\n\nPas besoin de tout comprendre dès le début. Avec le temps, vous apprendrez à repérer les chiffres clés.",
    quiz: [
      { id: 'q8', question: 'Que montre le BPA (Bénéfice Par Action) ?', options: ['Le prix de l\'action', 'Le profit généré par chaque action', 'Le nombre d\'actionnaires', 'Les dettes de l\'entreprise'], correctIndex: 1 },
    ],
  },
  {
    id: '8', title: 'Les erreurs classiques du débutant', duration: '4 min', status: 'locked',
    content: "Erreur #1 : Paniquer et vendre quand le marché baisse. Les baisses sont normales et temporaires.\n\nErreur #2 : Vérifier son portefeuille toutes les heures. Les variations quotidiennes ne sont pas significatives.\n\nErreur #3 : Suivre les \"conseils\" sur les réseaux sociaux. La plupart sont de mauvaise qualité.\n\nErreur #4 : Ne pas diversifier. Mettre tout son argent sur une seule action est risqué.\n\nErreur #5 : Investir de l'argent dont on a besoin à court terme. N'investissez que ce que vous pouvez vous permettre de laisser pendant au moins 5 ans.",
    quiz: [
      { id: 'q9', question: 'Quelle est une erreur classique du débutant ?', options: ['Diversifier son portefeuille', 'Investir sur le long terme', 'Paniquer et vendre quand le marché baisse', 'Lire les rapports financiers'], correctIndex: 2 },
    ],
  },
  {
    id: '9', title: 'Investissement long terme vs court terme', duration: '4 min', status: 'locked',
    content: "L'investissement court terme (trading) consiste à acheter et vendre fréquemment pour profiter des variations de prix. C'est risqué et chronophage.\n\nL'investissement long terme consiste à acheter et garder ses actions pendant plusieurs années. Historiquement, c'est la stratégie la plus rentable.\n\nLe S&P 500 a offert un rendement annuel moyen d'environ 10% sur les 50 dernières années, malgré des crises et des baisses temporaires.\n\nVotre coffret Krezus est conçu pour l'investissement long terme. Laissez le temps faire son travail !",
    quiz: [
      { id: 'q10', question: 'Quelle stratégie est historiquement la plus rentable ?', options: ['Le day trading', 'L\'investissement long terme', 'Garder son argent sous le matelas', 'Changer d\'actions chaque mois'], correctIndex: 1 },
    ],
  },
  {
    id: '10', title: 'Les frais et la fiscalité', duration: '5 min', status: 'locked',
    content: "Les frais de gestion sont prélevés par la plateforme qui gère vos actions. Chez Krezus, les frais sont inclus dans le coffret.\n\nLa fiscalité : en France, les plus-values sur les actions sont soumises au PFU (Prélèvement Forfaitaire Unique) de 30%, ou au barème de l'impôt sur le revenu.\n\nLes dividendes sont aussi soumis au PFU de 30%.\n\nBonne nouvelle : vous ne payez des impôts que quand vous vendez vos actions et réalisez une plus-value. Tant que vous gardez vos actions, rien à payer sur les plus-values latentes.",
    quiz: [
      { id: 'q11', question: 'Quand payez-vous des impôts sur vos actions ?', options: ['Chaque année', 'Quand vous vendez et réalisez une plus-value', 'Jamais', 'Quand le prix monte'], correctIndex: 1 },
    ],
  },
  {
    id: '11', title: 'Construire sa stratégie', duration: '4 min', status: 'locked',
    content: "Une stratégie d'investissement commence par définir vos objectifs : épargne retraite, projet immobilier, liberté financière...\n\nDéterminez votre horizon de temps : plus il est long, plus vous pouvez prendre de risques.\n\nÉvaluez votre tolérance au risque : êtes-vous à l'aise avec des fluctuations importantes ?\n\nL'investissement régulier (DCA - Dollar Cost Averaging) est une stratégie simple et efficace : investir un montant fixe chaque mois, quel que soit le prix du marché.\n\nVotre coffret Krezus est un excellent premier pas. La prochaine étape pourrait être d'investir régulièrement pour construire votre patrimoine.",
    quiz: [
      { id: 'q12', question: 'Que signifie DCA ?', options: ['Daily Cash Account', 'Dollar Cost Averaging', 'Direct Capital Access', 'Dividende Cumulé Annuel'], correctIndex: 1 },
    ],
  },
  {
    id: '12', title: 'Prochaines étapes : aller plus loin', duration: '3 min', status: 'locked',
    content: "Félicitations ! Vous avez complété le parcours éducatif Krezus. Vous avez maintenant les bases pour comprendre le monde de l'investissement.\n\nPour aller plus loin :\n\n1. Ouvrez un PEA (Plan d'Épargne en Actions) pour bénéficier d'avantages fiscaux\n2. Commencez à investir régulièrement, même de petits montants\n3. Lisez des livres de référence comme \"L'investisseur intelligent\" de Benjamin Graham\n4. Suivez l'actualité économique sans obsession\n5. Rejoignez une communauté d'investisseurs pour apprendre des autres\n\nVotre aventure boursière ne fait que commencer !",
    quiz: [
      { id: 'q13', question: 'Quel est l\'avantage principal d\'un PEA ?', options: ['Pas de frais', 'Des avantages fiscaux', 'Un rendement garanti', 'L\'accès à plus d\'actions'], correctIndex: 1 },
    ],
  },
];

export const mockNews: NewsArticle[] = [
  {
    id: '1',
    title: 'Apple dévoile son nouveau casque Vision Pro 2',
    source: 'Les Échos',
    date: '2026-04-01',
    imageUrl: 'https://picsum.photos/200/120?random=1',
    url: 'https://example.com/news/1',
  },
  {
    id: '2',
    title: 'Les résultats Q1 d\'Apple dépassent les attentes',
    source: 'BFM Bourse',
    date: '2026-03-28',
    imageUrl: 'https://picsum.photos/200/120?random=2',
    url: 'https://example.com/news/2',
  },
  {
    id: '3',
    title: 'Apple investit 10 milliards dans l\'IA',
    source: 'Le Figaro',
    date: '2026-03-20',
    imageUrl: 'https://picsum.photos/200/120?random=3',
    url: 'https://example.com/news/3',
  },
];

export const mockGiftReveal: GiftReveal = {
  stocks: [
    { ticker: 'AAPL', name: 'Apple Inc.', logoUrl: 'https://logo.clearbit.com/apple.com', shares: 2.5 },
    { ticker: 'MSFT', name: 'Microsoft Corp.', logoUrl: 'https://logo.clearbit.com/microsoft.com', shares: 1.0 },
    { ticker: 'MC.PA', name: 'LVMH', logoUrl: 'https://logo.clearbit.com/lvmh.com', shares: 0.5 },
  ],
  initialValue: 1247.53,
  personalMessage: 'Joyeux anniversaire ! J\'espère que ce cadeau t\'ouvrira les portes du monde de l\'investissement. Avec tout mon amour. 💛',
  giftedBy: 'Marie',
};

// Seeded PRNG for deterministic chart data (replaces Math.random())
function seededRandom(seed: number): () => number {
  let s = seed;
  return () => {
    s = (s * 16807 + 0) % 2147483647;
    return (s - 1) / 2147483646;
  };
}

// Cache generated chart data so curves don't change on re-render/navigation
const chartDataCache = new Map<string, ChartDataPoint[]>();

function getPeriodConfig(period: string): { interval: number; points: number } {
  switch (period) {
    case '1J': return { interval: 5 * 60 * 1000, points: 78 };
    case '1S': return { interval: 2 * 60 * 60 * 1000, points: 84 };
    case '1M': return { interval: 24 * 60 * 60 * 1000, points: 30 };
    case '3M': return { interval: 24 * 60 * 60 * 1000, points: 90 };
    case '6M': return { interval: 24 * 60 * 60 * 1000, points: 180 };
    case '1A': return { interval: 7 * 24 * 60 * 60 * 1000, points: 52 };
    default: return { interval: 30 * 24 * 60 * 60 * 1000, points: 24 };
  }
}

// TODO: Replace with real API call (Alpha Vantage / Finnhub) when backend is ready
export function generateChartData(period: string): ChartDataPoint[] {
  const cacheKey = `portfolio_${period}`;
  const cached = chartDataCache.get(cacheKey);
  if (cached) return cached;

  const now = Date.now();
  const { interval, points } = getPeriodConfig(period);
  const baseValue = 1200;
  const random = seededRandom(period.length * 1000 + 42);

  const data: ChartDataPoint[] = [];
  let value = baseValue;

  for (let i = 0; i < points; i++) {
    const change = (random() - 0.45) * 15;
    value = Math.max(value + change, baseValue * 0.85);
    data.push({
      timestamp: now - (points - i) * interval,
      value: parseFloat(value.toFixed(2)),
    });
  }

  chartDataCache.set(cacheKey, data);
  return data;
}

// TODO: Replace with real API call (Alpha Vantage / Finnhub) when backend is ready
export function generateStockChartData(period: string, basePrice: number): ChartDataPoint[] {
  const cacheKey = `stock_${basePrice}_${period}`;
  const cached = chartDataCache.get(cacheKey);
  if (cached) return cached;

  const now = Date.now();
  const { interval, points } = getPeriodConfig(period);
  const random = seededRandom(Math.round(basePrice * 100) + period.length * 777);

  const data: ChartDataPoint[] = [];
  let value = basePrice * 0.9;

  for (let i = 0; i < points; i++) {
    const change = (random() - 0.45) * (basePrice * 0.02);
    value = Math.max(value + change, basePrice * 0.75);
    data.push({
      timestamp: now - (points - i) * interval,
      value: parseFloat(value.toFixed(2)),
    });
  }

  chartDataCache.set(cacheKey, data);
  return data;
}
