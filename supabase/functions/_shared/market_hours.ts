// =====================================================================
// Heures de marché — pilote la cadence de rafraîchissement du cache.
//
// Euronext Paris : 09:00–17:30 (Europe/Paris)
// NASDAQ / NYSE  : 09:30–16:00 (America/New_York)
//
// Les fuseaux sont résolus via Intl plutôt qu'avec un décalage codé en dur :
// Paris et New York ne basculent pas à l'heure d'été aux mêmes dates, il
// existe chaque année deux fenêtres où l'écart n'est pas de 6 heures.
//
// Les jours fériés boursiers ne sont PAS gérés en v1 : le seul effet est un
// rafraîchissement inutile (le cours renvoyé est la dernière clôture), ce qui
// coûte quelques appels sur un quota de 100 000/jour. Un calendrier serait
// nécessaire si l'on voulait afficher « marché fermé » à l'utilisateur.
// =====================================================================

export type Session = "euronext" | "us" | "both" | "closed";

interface ZonedTime {
  /** 1 = lundi … 7 = dimanche (ISO 8601). */
  weekday: number;
  /** Minutes écoulées depuis minuit, heure locale du fuseau. */
  minutes: number;
}

const WEEKDAYS: Record<string, number> = {
  Mon: 1, Tue: 2, Wed: 3, Thu: 4, Fri: 5, Sat: 6, Sun: 7,
};

export function zonedTime(date: Date, timeZone: string): ZonedTime {
  const parts = new Intl.DateTimeFormat("en-US", {
    timeZone,
    weekday: "short",
    hour: "2-digit",
    minute: "2-digit",
    hour12: false,
  }).formatToParts(date);

  const get = (type: string) => parts.find((p) => p.type === type)?.value ?? "";
  const weekday = WEEKDAYS[get("weekday")] ?? 0;

  // En hour12:false, minuit peut être rendu « 24 » selon la plateforme.
  const hour = Number(get("hour")) % 24;
  const minute = Number(get("minute"));

  return { weekday, minutes: hour * 60 + minute };
}

function isOpen(date: Date, timeZone: string, openMin: number, closeMin: number): boolean {
  const { weekday, minutes } = zonedTime(date, timeZone);
  if (weekday < 1 || weekday > 5) return false;
  return minutes >= openMin && minutes < closeMin;
}

export function isEuronextOpen(date: Date): boolean {
  return isOpen(date, "Europe/Paris", 9 * 60, 17 * 60 + 30);
}

export function isUSMarketOpen(date: Date): boolean {
  return isOpen(date, "America/New_York", 9 * 60 + 30, 16 * 60);
}

export function currentSession(date: Date): Session {
  const eu = isEuronextOpen(date);
  const us = isUSMarketOpen(date);
  if (eu && us) return "both";
  if (eu) return "euronext";
  if (us) return "us";
  return "closed";
}

/**
 * Le moteur d'ordres rejette une cotation vieille de plus de 15 minutes
 * (SQLSTATE KR004). Hors séance, on continue donc de rafraîchir — plus
 * lentement — pour que le cache reste « frais » et qu'un ordre passé le soir
 * s'exécute à la dernière clôture, au lieu d'échouer sans explication.
 */
export function refreshIntervalSeconds(session: Session): number {
  return session === "closed" ? 600 : 60;
}

// ---------------------------------------------------------------------
// Heures d'ouverture par place.
//
// Depuis que le référentiel compte plus de mille titres, on ne rafraîchit
// plus tout à chaque minute : chaque titre coûte un appel EODHD, et le
// quota est de 100 000 par jour. Il faut donc savoir, titre par titre, si
// sa place est ouverte. Le suffixe du symbole EODHD désigne la place.
// ---------------------------------------------------------------------

interface ExchangeHours {
  timeZone: string;
  /** Ouverture et clôture, en minutes depuis minuit, heure locale. */
  open: number;
  close: number;
}

const HOURS = {
  europe: { timeZone: "Europe/Paris", open: 9 * 60, close: 17 * 60 + 30 },
  london: { timeZone: "Europe/London", open: 8 * 60, close: 16 * 60 + 30 },
  zurich: { timeZone: "Europe/Zurich", open: 9 * 60, close: 17 * 60 + 30 },
  nordic: { timeZone: "Europe/Stockholm", open: 9 * 60, close: 17 * 60 + 30 },
  us:     { timeZone: "America/New_York", open: 9 * 60 + 30, close: 16 * 60 },
  toronto: { timeZone: "America/Toronto", open: 9 * 60 + 30, close: 16 * 60 },
  tokyo:  { timeZone: "Asia/Tokyo", open: 9 * 60, close: 15 * 60 + 30 },
  hongkong: { timeZone: "Asia/Hong_Kong", open: 9 * 60 + 30, close: 16 * 60 },
  seoul:  { timeZone: "Asia/Seoul", open: 9 * 60, close: 15 * 60 + 30 },
} satisfies Record<string, ExchangeHours>;

/** Suffixe EODHD -> horaires. Place inconnue : horaires européens. */
const EXCHANGES: Record<string, ExchangeHours> = {
  PA: HOURS.europe, AS: HOURS.europe, BR: HOURS.europe, LS: HOURS.europe,
  XETRA: HOURS.europe, F: HOURS.europe, MC: HOURS.europe, MI: HOURS.europe,
  VI: HOURS.europe, IR: HOURS.europe, HE: HOURS.europe,
  LSE: HOURS.london,
  SW: HOURS.zurich,
  ST: HOURS.nordic, CO: HOURS.nordic, OL: HOURS.nordic,
  US: HOURS.us,
  TO: HOURS.toronto,
  TSE: HOURS.tokyo,
  HK: HOURS.hongkong,
  KO: HOURS.seoul,
};

/** « MC.PA » -> « PA », « AAPL.US » -> « US ». */
export function exchangeOf(eodhdSymbol: string): string {
  const dot = eodhdSymbol.lastIndexOf(".");
  return dot < 0 ? "US" : eodhdSymbol.slice(dot + 1).toUpperCase();
}

export function isExchangeOpen(exchange: string, date: Date): boolean {
  const hours = EXCHANGES[exchange.toUpperCase()] ?? HOURS.europe;
  return isOpen(date, hours.timeZone, hours.open, hours.close);
}
