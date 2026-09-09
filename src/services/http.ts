import { REQUEST_TIMEOUT_MS } from './config';

/** Erreur réseau/API normalisée : le `status` permet de distinguer 403 (endpoint premium) de 429 (quota). */
export class ApiError extends Error {
  constructor(message: string, public readonly status?: number) {
    super(message);
    this.name = 'ApiError';
  }
}

/**
 * `fetch` JSON avec timeout. Volontairement sans dépendance HTTP externe :
 * `fetch` est fourni par React Native.
 */
export async function fetchJson<T>(
  url: string,
  timeoutMs: number = REQUEST_TIMEOUT_MS
): Promise<T> {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);

  try {
    const response = await fetch(url, {
      signal: controller.signal,
      headers: { Accept: 'application/json' },
    });

    if (!response.ok) {
      throw new ApiError(
        `Requête refusée par le fournisseur de données (HTTP ${response.status})`,
        response.status
      );
    }

    return (await response.json()) as T;
  } catch (error) {
    if (error instanceof ApiError) throw error;
    if (error instanceof Error && error.name === 'AbortError') {
      throw new ApiError(`Délai dépassé après ${timeoutMs} ms`);
    }
    throw new ApiError(
      error instanceof Error ? error.message : 'Erreur réseau inconnue'
    );
  } finally {
    clearTimeout(timer);
  }
}
