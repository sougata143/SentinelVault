import * as crypto from 'crypto';

/**
 * Converts a BigInt to a big-endian Buffer padded to the specified length.
 */
export function bigIntToBuffer(num: bigint, length: number): Buffer {
  let hex = num.toString(16);
  if (hex.length % 2 !== 0) {
    hex = '0' + hex;
  }
  const buf = Buffer.from(hex, 'hex');
  if (buf.length === length) {
    return buf;
  }
  if (buf.length > length) {
    return buf.subarray(buf.length - length);
  }
  const padded = Buffer.alloc(length);
  buf.copy(padded, length - buf.length);
  return padded;
}

/**
 * Converts a Buffer to a positive bigint.
 */
export function bufferToBigInt(buf: Buffer): bigint {
  return BigInt('0x' + buf.toString('hex'));
}

/**
 * Computes SHA-256 hash of the input Buffer.
 */
export function sha256(data: Buffer): Buffer {
  return crypto.createHash('sha256').update(data).digest();
}

/**
 * Server-side Secure Remote Password (SRP-6a) authentication logic.
 *
 * Implements RFC 5054 2048-bit prime group calculations.
 */
export class SrpServer {
  public static readonly N = BigInt(
    '0xAC6BDB41324A9A9BF166DE5E1389582FAF72B6651987EE07FC332F683B94471B' +
    'A25CEB5F15DE38B4341168461CCBA0140F00D0160AFFA93DD2C85E247E674003' +
    '79E0957D0502438DF02B22B647CA55F2A3841D39634992644265EEBEC4D20A16' +
    'C5F3528A6D15E4407B18E06A53ED9027D9B420C21C313E1B2749591A9B65438A' +
    '2566CCC4465B2035F121210850D6955DFEB4CD0EE5460E58F69646FA5E4B4957' +
    'B733B9B47E53B026BE6395EE1B24E7985474D5409605553E4774B819EF66E2E1' +
    '9C898394EAEEDC4C7E9C4CC295F8CCE8CC991666CB29A51F2231BC7FF2FB81C7' +
    '89FE2CA0B83EAD80A3A059B51E13D667793B9F2EA2F29A58814D7964E94EA25D'
  );

  public static readonly g = BigInt(2);

  private static kCache: bigint | null = null;

  /**
   * Retrieves the multiplier k = H(N, g).
   */
  public static getMultiplierK(): bigint {
    if (this.kCache !== null) {
      return this.kCache;
    }
    const nBytes = bigIntToBuffer(this.N, 256);
    const gBytes = bigIntToBuffer(this.g, 256);
    const combined = Buffer.concat([nBytes, gBytes]);
    const hash = sha256(combined);
    this.kCache = bufferToBigInt(hash);
    return this.kCache;
  }

  /**
   * Computes modular exponentiation base^exp % mod using BigInt.
   */
  public static modPow(base: bigint, exp: bigint, mod: bigint): bigint {
    if (mod === BigInt(0)) return BigInt(0);
    let result = BigInt(1);
    let b = (base % mod + mod) % mod;
    let e = exp;
    while (e > BigInt(0)) {
      if (e % BigInt(2) === BigInt(1)) {
        result = (result * b) % mod;
      }
      b = (b * b) % mod;
      e = e / BigInt(2);
    }
    return result;
  }

  /**
   * Generates server ephemeral secret [b] and challenge public [B].
   */
  public static generateServerEphemeral(v: bigint, secureRandomBytes: Buffer): { secret: bigint; publicValue: bigint } {
    const b = bufferToBigInt(secureRandomBytes) % this.N;
    const k = this.getMultiplierK();

    // B = (k*v + g^b) mod N
    const gb = this.modPow(this.g, b, this.N);
    const kv = (k * v) % this.N;
    const B = (kv + gb) % this.N;

    return { secret: b, publicValue: B };
  }

  /**
   * Computes scrambling parameter u = H(A, B).
   */
  public static calculateU(A: bigint, B: bigint): bigint {
    const aBytes = bigIntToBuffer(A, 256);
    const bBytes = bigIntToBuffer(B, 256);
    const uInput = Buffer.concat([aBytes, bBytes]);
    return bufferToBigInt(sha256(uInput));
  }

  /**
   * Verifies the client's evidence M1 and computes mutual evidence M2.
   */
  public static verifySession({
    username,
    salt,
    A,
    B,
    v,
    b,
    clientEvidence,
  }: {
    username: string;
    salt: Buffer;
    A: bigint;
    B: bigint;
    v: bigint;
    b: bigint;
    clientEvidence: Buffer;
  }): { success: boolean; serverEvidence: Buffer | null; sessionKey: Buffer | null } {
    if (A % this.N === BigInt(0)) {
      return { success: false, serverEvidence: null, sessionKey: null };
    }

    const u = this.calculateU(A, B);
    if (u === BigInt(0)) {
      return { success: false, serverEvidence: null, sessionKey: null };
    }

    // S = (A * v^u) ^ b mod N
    const vu = this.modPow(v, u, this.N);
    const base = (A * vu) % this.N;
    const S = this.modPow(base, b, this.N);

    const sBytes = bigIntToBuffer(S, 256);
    const sessionKey = sha256(sBytes);

    // Compute expected M1 = H(H(N) ^ H(g), H(username), salt, A, B, sessionKey)
    const hn = sha256(bigIntToBuffer(this.N, 256));
    const hg = sha256(bigIntToBuffer(this.g, 256));
    const hXor = Buffer.alloc(32);
    for (let i = 0; i < 32; i++) {
      hXor[i] = hn[i] ^ hg[i];
    }

    const hu = sha256(Buffer.from(username, 'utf-8'));
    const aBytes = bigIntToBuffer(A, 256);
    const bBytes = bigIntToBuffer(B, 256);

    const m1Input = Buffer.concat([hXor, hu, salt, aBytes, bBytes, sessionKey]);
    const expectedM1 = sha256(m1Input);

    if (!crypto.timingSafeEqual(clientEvidence, expectedM1)) {
      return { success: false, serverEvidence: null, sessionKey: null };
    }

    // Compute server evidence M2 = H(A, M1, sessionKey)
    const m2Input = Buffer.concat([aBytes, expectedM1, sessionKey]);
    const serverEvidence = sha256(m2Input);

    return {
      success: true,
      serverEvidence,
      sessionKey,
    };
  }
}
