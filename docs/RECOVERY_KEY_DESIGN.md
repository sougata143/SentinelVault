# Cryptographic Design: Emergency Kit Recovery Key

This document proposes the cryptographic construction for the SentinelVault Emergency Kit Recovery Key. The goal is to allow a user to regain access to their Vault Key ($VK$) if they forget their Master Password ($MP$), without introducing any server-side backdoor and without weakening the Master-Password-only unlock path.

---

## Security & Design Goals

1. **Zero-Knowledge Compliance**: The server must never learn the Vault Key ($VK$), the Master Password ($MP$), or the Recovery Key ($RK$).
2. **Independent Security Paths**: The recovery path must not weaken the security of the Master Password path. A compromise of one path must not compromise the other.
3. **No Server Backdoors**: The server must not be able to decrypt the vault or bypass authentication, even if compromised.
4. **Volatile Memory Execution**: Recovery operations and key unwrapping must happen entirely client-side in volatile memory.

---

## Candidate 1: Dual Key-Wrapping (Independent Encryption)

In this construction, the client-generated random Vault Key ($VK$) is encrypted independently under two different keys: the Master Key ($MK$, derived from the Master Password) and the Recovery KDF Key ($RKK$, derived from the Recovery Key).

```
                      ┌────────────────────────────────────────┐
                      │               Vault Key (VK)           │
                      └───────────┬────────────────┬───────────┘
                                  │                │
            Wrap via MK           │                │           Wrap via RKK
           (Argon2id KDF)         ▼                ▼          (Argon2id KDF)
                       ┌─────────────┐          ┌─────────────┐
                       │  AES-GCM    │          │  AES-GCM    │
                       └──────┬──────┘          └──────┬──────┘
                              ▼                        ▼
                       Wrapped Key (MP)         Wrapped Key (RK)
                       (WVK_mp to Sync)         (WVK_rk to Sync)
```

### Protocol Steps

1. **Initialization**:
   - The client generates a cryptographically secure random 256-bit Vault Key ($VK$).
   - The client generates a high-entropy random 256-bit Recovery Key ($RK$) (represented as a 32-character alphanumeric or 12-word mnemonic phrase).
   - The client derives:
     - $MK = Argon2id(MP, salt_{mp})$
     - $RKK = Argon2id(RK, salt_{rk})$
   - The client encrypts:
     - $WVK_{mp} = AES-256-GCM(MK, VK, nonce_{mp})$
     - $WVK_{rk} = AES-256-GCM(RKK, VK, nonce_{rk})$
   - The client uploads $\{salt_{mp}, WVK_{mp}\}$ and $\{salt_{rk}, WVK_{rk}\}$ to the sync server.

2. **Recovery Flow**:
   - The user inputs the Recovery Key ($RK$).
   - The client downloads $\{salt_{rk}, WVK_{rk}\}$ from the server.
   - The client derives $RKK = Argon2id(RK, salt_{rk})$.
   - The client decrypts $VK = AES-256-GCM\_Decrypt(RKK, WVK_{rk}, nonce_{rk})$.
   - On success, the user is prompted to establish a new Master Password ($MP_{new}$), generating a new $WVK_{mp\_new}$ to upload to the server.

### Tradeoffs
- **Security**: Excellent. The Master Password KDF parameters ($64\,\text{MB}$ memory, 3 iterations) remain unchanged. The Recovery Key has extremely high entropy (256-bit), making it immune to offline brute-force attacks even if the wrapped key ciphertext $WVK_{rk}$ is intercepted from the sync server.
- **Implementation Complexity**: Low. Reuses existing `Argon2id` and `AES-256-GCM` primitives from the `VaultCrypto` library.
- **Sync Protocol Impact**: Low. Requires storing one additional wrapped key record (`salt_rk` and `wrapped_key_rk`) per user on the server.

---

## Candidate 2: In-Memory XOR Secret Sharing (Key Splitting)

In this construction, the Vault Key ($VK$) is split into two random shares ($S_{server}$ and $S_{client}$) using a 2-of-2 XOR secret sharing scheme:
$$VK = S_{server} \oplus S_{client}$$
- $S_{server}$ is stored encrypted on the server (wrapped by the Master Key).
- $S_{client}$ is printed in the Emergency Kit as the Recovery Key.

```
                      ┌────────────────────────────────────────┐
                      │               Vault Key (VK)           │
                      └───────────┬────────────────┬───────────┘
                                  │                │
                                  ▼                ▼
                           ┌─────────────┐  ┌─────────────┐
                           │  Server     │  │  Client     │
                           │  Share      │  │  Share      │
                           │  (S_server) │  │  (S_client) │
                           └──────┬──────┘  └──────┬──────┘
                                  │                │
                         Wrap via │                │ Printed Offline
                            MK    ▼                ▼ (Recovery Key)
                            ┌───────────┐      Emergency Kit
                            │  AES-GCM  │
                            └─────┬─────┘
                                  ▼
                            Wrapped Share
                            (to Sync DB)
```

### Protocol Steps

1. **Initialization**:
   - The client generates a random Vault Key ($VK$).
   - The client generates a random share $S_{client}$ (the Recovery Key, printed once for the user).
   - The client computes the server's share:
     $$S_{server} = VK \oplus S_{client}$$
   - The client encrypts $S_{server}$ using the derived Master Key:
     $$W\!S_{server} = AES-256-GCM(MK, S_{server}, nonce)$$
   - The client uploads $W\!S_{server}$ and $salt_{mp}$ to the sync server. The client also uploads the standard $WVK_{mp} = AES-256-GCM(MK, VK, nonce)$ for daily logins.

2. **Recovery Flow**:
   - The user inputs the Recovery Key ($S_{client}$).
   - The client downloads $W\!S_{server}$ from the server.
   - The client decrypts $S_{server}$ using the Master Key? No, if the user forgot their Master Password, they *cannot* decrypt $W\!S_{server}$ if it is wrapped by $MK$!
   - Ah! To allow recovery without the Master Password, $S_{server}$ must *not* be wrapped by $MK$. It must be stored in plaintext on the server (or encrypted by a server-side key, though storing it in plaintext is safe because the server has no access to $S_{client}$).
   - So $S_{server}$ is stored directly on the sync server.
   - The client computes $VK = S_{server} \oplus S_{client}$.

### Tradeoffs
- **Security**: Information-theoretically secure. The server only holds $S_{server}$, and the user holds $S_{client}$. Neither party alone gains any information about $VK$.
- **Vulnerability to Offline Attacks**: Excellent. If the server is compromised, the attacker only gets $S_{server}$, which is a completely random bit string, giving zero information about $VK$.
- **Usability Tradeoff**: The Recovery Key $S_{client}$ must be a raw binary key (e.g. 256-bit represented as a long string) and cannot be derived from a password.
- **Loss of Server Share**: If the server database is corrupted or lost, the user's offline Emergency Kit is useless because $S_{server}$ is missing. In Candidate 1, if the server is lost, the user still has their local encrypted database replica, and the recovery key can decrypt the local replica because it contains all the cryptographic material needed locally.

---

## Proposed Recommendation: **Candidate 1 (Dual Key-Wrapping)**

We recommend **Candidate 1** for the following reasons:
1. **Offline Autonomy**: It does not depend on the server for decryption during a local recovery. If the user has a local replica of the encrypted database (offline-first), they can decrypt it directly using their printed Recovery Key, even if the cloud server is offline or the account database is lost.
2. **Implementation Consistency**: It aligns perfectly with the zero-knowledge sync protocol already established for the Master Password and does not introduce raw plaintext shares to the sync database.
