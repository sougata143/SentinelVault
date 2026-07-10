/**
 * In-memory store for per-user breach metadata.
 *
 * Keys are opaque identifiers (SHA-256 of the user's email) so the store
 * itself never holds raw email addresses.
 *
 * Only breach metadata is persisted:  { name, breachDate, dataClasses }.
 * The raw email and full HIBP API responses are never stored.
 */
export interface BreachEntry {
  name: string;
  breachDate: string;
  dataClasses: string[];
}

/**
 * Simple in-memory store.  In production this would be backed by a database,
 * but the interface contract (emailHash → BreachEntry[]) remains the same.
 */
export class BreachStore {
  /** Map from opaque emailHash → array of known breach metadata. */
  private readonly store = new Map<string, BreachEntry[]>();

  /** Opted-in email hashes together with their (encrypted) email address. */
  private readonly optIns = new Map<string, string>();

  /** Records that [emailHash] has opted in, storing the associated email for scheduling. */
  optIn(emailHash: string, email: string): void {
    this.optIns.set(emailHash, email);
    if (!this.store.has(emailHash)) {
      this.store.set(emailHash, []);
    }
  }

  /** Removes an email hash from opt-in monitoring. */
  optOut(emailHash: string): void {
    this.optIns.delete(emailHash);
    this.store.delete(emailHash);
  }

  /** Returns true if [emailHash] is currently opted in. */
  isOptedIn(emailHash: string): boolean {
    return this.optIns.has(emailHash);
  }

  /** Returns the email associated with [emailHash], or undefined if not opted in. */
  getEmail(emailHash: string): string | undefined {
    return this.optIns.get(emailHash);
  }

  /** Returns all opted-in email hashes. */
  allOptedInHashes(): string[] {
    return Array.from(this.optIns.keys());
  }

  /** Returns the stored breaches for [emailHash]. */
  getBreaches(emailHash: string): BreachEntry[] {
    return this.store.get(emailHash) ?? [];
  }

  /**
   * Updates the stored breaches for [emailHash] and returns only the
   * *new* entries that were not previously known.
   */
  updateBreaches(emailHash: string, incoming: BreachEntry[]): BreachEntry[] {
    const existing = this.store.get(emailHash) ?? [];
    const existingNames = new Set(existing.map((b) => b.name));
    const newBreaches = incoming.filter((b) => !existingNames.has(b.name));
    this.store.set(emailHash, [...existing, ...newBreaches]);
    return newBreaches;
  }
}
