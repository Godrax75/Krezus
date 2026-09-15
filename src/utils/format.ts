const SYMBOLS: Record<string, string> = { EUR: '€', USD: '$' };

/**
 * Formate un montant avec la devise réellement cotée.
 * Les cours US sont convertis en euros quand le taux de change est
 * disponible ; sinon on affiche des dollars plutôt qu'un montant faux.
 */
export function formatMoney(value: number, currency: string = 'EUR'): string {
  return `${value.toFixed(2)} ${SYMBOLS[currency] ?? currency}`;
}

/** Idem, avec le signe explicite pour les plus/moins-values. */
export function formatSignedMoney(value: number, currency: string = 'EUR'): string {
  return `${value >= 0 ? '+' : ''}${formatMoney(value, currency)}`;
}
