/* tslint:disable */
/* eslint-disable */

export function wasmDecryptAesGcm(key: Uint8Array, nonce: Uint8Array, ciphertext: Uint8Array): Uint8Array;

export function wasmDeriveMasterKey(password: Uint8Array, salt: Uint8Array): Uint8Array;

export function wasmEncryptAesGcm(key: Uint8Array, nonce: Uint8Array, plaintext: Uint8Array): Uint8Array;

export function wasmShamirCombine(flat_shares: Uint8Array): Uint8Array;

export function wasmShamirSplit(secret: Uint8Array, m: number, n: number): Uint8Array;

export function wasmSrpCalculateClientSession(username: string, salt: Uint8Array, a_bytes: Uint8Array, a_pub_bytes: Uint8Array, b_pub_bytes: Uint8Array, master_key: Uint8Array): Uint8Array;

export function wasmSrpCalculateVerifier(username: string, master_key: Uint8Array, salt: Uint8Array): Uint8Array;

export function wasmSrpCalculateX(username: string, master_key: Uint8Array, salt: Uint8Array): Uint8Array;

export function wasmSrpGenerateClientEphemeral(a_bytes: Uint8Array): Uint8Array;

export type InitInput = RequestInfo | URL | Response | BufferSource | WebAssembly.Module;

export interface InitOutput {
    readonly memory: WebAssembly.Memory;
    readonly decrypt_aes_gcm: (a: number, b: number, c: number, d: number, e: number, f: number, g: number) => number;
    readonly derive_master_key: (a: number, b: number, c: number, d: number, e: number) => number;
    readonly encrypt_aes_gcm: (a: number, b: number, c: number, d: number, e: number, f: number, g: number) => number;
    readonly pqc_generate_keypairs: (a: number, b: number, c: number) => number;
    readonly pqc_hybrid_unwrap: (a: number, b: number, c: number, d: number, e: number, f: number, g: number, h: number, i: number, j: number) => number;
    readonly pqc_hybrid_wrap: (a: number, b: number, c: number, d: number, e: number, f: number, g: number) => number;
    readonly pqc_sign_invitation: (a: number, b: number, c: number, d: number, e: number, f: number, g: number) => number;
    readonly pqc_verify_invitation: (a: number, b: number, c: number, d: number, e: number, f: number, g: number, h: number) => number;
    readonly shamir_combine: (a: number, b: number, c: number, d: number, e: number) => number;
    readonly shamir_split: (a: number, b: number, c: number, d: number, e: number, f: number, g: number) => number;
    readonly srp_calculate_client_session: (a: number, b: number, c: number, d: number, e: number, f: number, g: number, h: number, i: number, j: number, k: number, l: number) => number;
    readonly srp_calculate_verifier: (a: number, b: number, c: number, d: number, e: number, f: number, g: number) => number;
    readonly srp_calculate_x: (a: number, b: number, c: number, d: number, e: number, f: number, g: number) => number;
    readonly srp_generate_client_ephemeral: (a: number, b: number, c: number, d: number) => number;
    readonly wasmDecryptAesGcm: (a: number, b: number, c: number, d: number, e: number, f: number) => [number, number, number, number];
    readonly wasmDeriveMasterKey: (a: number, b: number, c: number, d: number) => [number, number, number, number];
    readonly wasmEncryptAesGcm: (a: number, b: number, c: number, d: number, e: number, f: number) => [number, number, number, number];
    readonly wasmShamirCombine: (a: number, b: number) => [number, number, number, number];
    readonly wasmShamirSplit: (a: number, b: number, c: number, d: number) => [number, number, number, number];
    readonly wasmSrpCalculateClientSession: (a: number, b: number, c: number, d: number, e: number, f: number, g: number, h: number, i: number, j: number, k: number, l: number) => [number, number, number, number];
    readonly wasmSrpCalculateVerifier: (a: number, b: number, c: number, d: number, e: number, f: number) => [number, number];
    readonly wasmSrpCalculateX: (a: number, b: number, c: number, d: number, e: number, f: number) => [number, number];
    readonly wasmSrpGenerateClientEphemeral: (a: number, b: number) => [number, number];
    readonly __wbindgen_exn_store: (a: number) => void;
    readonly __externref_table_alloc: () => number;
    readonly __wbindgen_externrefs: WebAssembly.Table;
    readonly __wbindgen_malloc: (a: number, b: number) => number;
    readonly __externref_table_dealloc: (a: number) => void;
    readonly __wbindgen_free: (a: number, b: number, c: number) => void;
    readonly __wbindgen_realloc: (a: number, b: number, c: number, d: number) => number;
    readonly __wbindgen_start: () => void;
}

export type SyncInitInput = BufferSource | WebAssembly.Module;

/**
 * Instantiates the given `module`, which can either be bytes or
 * a precompiled `WebAssembly.Module`.
 *
 * @param {{ module: SyncInitInput }} module - Passing `SyncInitInput` directly is deprecated.
 *
 * @returns {InitOutput}
 */
export function initSync(module: { module: SyncInitInput } | SyncInitInput): InitOutput;

/**
 * If `module_or_path` is {RequestInfo} or {URL}, makes a request and
 * for everything else, calls `WebAssembly.instantiate` directly.
 *
 * @param {{ module_or_path: InitInput | Promise<InitInput> }} module_or_path - Passing `InitInput` directly is deprecated.
 *
 * @returns {Promise<InitOutput>}
 */
export default function __wbg_init (module_or_path?: { module_or_path: InitInput | Promise<InitInput> } | InitInput | Promise<InitInput>): Promise<InitOutput>;
