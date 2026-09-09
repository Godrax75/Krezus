import { mockStocks } from '../data/mockData';

/**
 * Passerelle entre les identifiants internes et les symboles du fournisseur.
 *
 * Rappel du modèle de données : la clé de `mockStocks` n'est ni l'id ni le
 * ticker (clé `LVMH`, id `lvmh`, ticker `MC.PA`). Tout le reste de l'app
 * manipule le `stockId` en minuscules, donc c'est lui qui sert de pivot ici.
 */
export interface SymbolMapping {
  stockId: string;
  /** Symbole envoyé au fournisseur. */
  providerSymbol: string;
  /** Devise dans laquelle le fournisseur cote ce titre. */
  currency: 'USD' | 'EUR';
  /**
   * `false` pour les places hors États-Unis : le palier gratuit de Finnhub ne
   * couvre que le marché US. Ces lignes restent sur les données de démo.
   */
  supported: boolean;
}

const registry: Record<string, SymbolMapping> = Object.values(mockStocks).reduce(
  (acc, stock) => {
    // Un suffixe de place (`.PA`, `.DE`, …) signale un titre hors marché US.
    const hasExchangeSuffix = stock.ticker.includes('.');
    acc[stock.id.toLowerCase()] = {
      stockId: stock.id.toLowerCase(),
      providerSymbol: stock.ticker,
      currency: stock.ticker.endsWith('.PA') ? 'EUR' : 'USD',
      supported: !hasExchangeSuffix,
    };
    return acc;
  },
  {} as Record<string, SymbolMapping>
);

export function getSymbolMapping(stockId: string): SymbolMapping | null {
  return registry[stockId.toLowerCase()] ?? null;
}

/** Les identifiants pour lesquels on peut réellement interroger le fournisseur. */
export function getSupportedStockIds(): string[] {
  return Object.values(registry)
    .filter((mapping) => mapping.supported)
    .map((mapping) => mapping.stockId);
}
