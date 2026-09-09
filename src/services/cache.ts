/**
 * Cache mémoire à durée de vie, avec déduplication des requêtes en vol.
 *
 * Deux écrans qui demandent la même donnée en même temps (Accueil + détail)
 * ne déclenchent qu'un seul appel réseau, ce qui compte quand le palier
 * gratuit plafonne à 60 requêtes/minute.
 */

interface CacheEntry<T> {
  value: T;
  expiresAt: number;
}

export class TtlCache<T> {
  private entries = new Map<string, CacheEntry<T>>();
  private inflight = new Map<string, Promise<T>>();

  constructor(private readonly ttlMs: number) {}

  get(key: string): T | undefined {
    const entry = this.entries.get(key);
    if (!entry) return undefined;
    if (Date.now() > entry.expiresAt) {
      this.entries.delete(key);
      return undefined;
    }
    return entry.value;
  }

  set(key: string, value: T): void {
    this.entries.set(key, { value, expiresAt: Date.now() + this.ttlMs });
  }

  /**
   * Renvoie la valeur en cache, sinon exécute `loader` (une seule fois même si
   * plusieurs appelants arrivent en parallèle sur la même clé).
   */
  async resolve(key: string, loader: () => Promise<T>, force = false): Promise<T> {
    if (!force) {
      const cached = this.get(key);
      if (cached !== undefined) return cached;
    }

    const pending = this.inflight.get(key);
    if (pending) return pending;

    const request = loader()
      .then((value) => {
        this.set(key, value);
        return value;
      })
      .finally(() => {
        this.inflight.delete(key);
      });

    this.inflight.set(key, request);
    return request;
  }

  invalidate(key: string): void {
    this.entries.delete(key);
  }

  clear(): void {
    this.entries.clear();
  }
}
