import { Injectable } from '@nestjs/common';
import axios from 'axios';

@Injectable()
export class UrlReputationService {
  private readonly cache: Map<string, { verdict: string; timestamp: number }> = new Map();
  private readonly CACHE_TTL_MS = 60 * 1000; // Cache results for 1 minute

  // A local heuristic database of known bad domains for mock fallback / testing
  private readonly localBlacklist = new Set<string>([
    'malicious-domain.com',
    'phishing-site.xyz',
    'xn--pple-43d.com', // punycode homoglyph
    'аpple.com', // cyrillic homoglyph
    '192.168.1.1', // local IP literal
    '[2001:db8::1]', // IPv6 literal
  ]);

  /**
   * Looks up a domain in the reputation database (Google Safe Browsing API or local fallback).
   */
  public async lookup(domain: string): Promise<string> {
    const normalizedDomain = domain.trim().toLowerCase();
    
    // Check local cache first
    const cached = this.cache.get(normalizedDomain);
    if (cached && Date.now() - cached.timestamp < this.CACHE_TTL_MS) {
      return cached.verdict;
    }

    let verdict = 'safe';

    // 1. Check local blacklists (useful for testing or fallback when API key is missing)
    if (this.localBlacklist.has(normalizedDomain) || normalizedDomain.includes('security-alert')) {
      verdict = 'malicious';
    } else {
      // 2. Query Google Safe Browsing if API key is configured
      const apiKey = process.env.SAFE_BROWSING_API_KEY;
      if (apiKey) {
        try {
          const url = `https://safebrowsing.googleapis.com/v4/threatMatches:find?key=${apiKey}`;
          const response = await axios.post(
            url,
            {
              client: {
                clientId: 'sentinelvault-backend',
                clientVersion: '1.0.0',
              },
              threatInfo: {
                threatTypes: [
                  'MALWARE',
                  'SOCIAL_ENGINEERING',
                  'UNWANTED_SOFTWARE',
                  'POTENTIALLY_HARMFUL_APPLICATION',
                ],
                platformTypes: ['ANY_PLATFORM'],
                threatEntryTypes: ['URL'],
                threatEntries: [{ url: normalizedDomain }],
              },
            },
            { timeout: 3000 },
          );

          if (response.data && response.data.matches && response.data.matches.length > 0) {
            verdict = 'malicious';
          }
        } catch (_) {
          // If Safe Browsing call fails (e.g. timeout, quota, network), keep the local blacklist verdict
          // but return 'unknown' if it wasn't on the blacklist to follow rules of engagement (fail-safe)
          verdict = this.localBlacklist.has(normalizedDomain) ? 'malicious' : 'unknown';
        }
      }
    }

    // Cache the result
    this.cache.set(normalizedDomain, { verdict, timestamp: Date.now() });
    return verdict;
  }

  /**
   * Clears the reputation cache.
   */
  public clearCache(): void {
    this.cache.clear();
  }
}
