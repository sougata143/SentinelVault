---
name: duress-decoy-vault
description: Use when implementing the opt-in duress/decoy vault feature — a second, decoy-password-derived vault database that opens instead of the real one under coercion, plus the native hook that wipes the real vault's biometric/hardware-key cache on trigger. Read the limitations section before building the in-app messaging for this feature.
---

# Skill: Duress / Decoy Vault

## Objective
Give users under coercion a way to open a plausible, harmless decoy vault
instead of their real one, while a native hook simultaneously invalidates
the real vault's biometric/hardware-key quick-unlock cache — without
overpromising what the feature can guarantee.

## Design
- Two independently encrypted local databases:
  - **Vault Alpha (real)**: derived from the actual Master Password, as
    already built.
  - **Vault Beta (decoy)**: derived from a separate **Duress Password**,
    populated (at setup time, by the user) with plausible but harmless
    items.
- On the Unlock screen, entering the Duress Password behaves identically
  to a normal unlock from the user's perspective — same transition, same
  timing characteristics as a real unlock — but decrypts and opens Vault
  Beta.
- On a Duress Password match, a native hook must immediately zero the
  biometric-cached key and any hardware-key (CTAP2 `hmac-secret`)
  reference tied to Vault Alpha, forcing manual Master Password entry to
  ever access the real vault again on that device. This must not delete or
  otherwise touch Vault Alpha's actual encrypted data — only invalidate
  the *quick-unlock* caches for it.
- This entire feature is opt-in, set up explicitly by the user (choosing
  and confirming a Duress Password distinct from the Master Password, and
  populating Vault Beta with decoy content) — never enabled by default.

## Required in-app honesty about limitations
- Do not present this as an absolute guarantee. State plainly, in the
  setup flow: this feature reduces certain risks but cannot guarantee an
  adversary won't notice indicators such as multiple encrypted database
  files on the device, unusual storage/backup patterns, or public
  knowledge that this app offers a duress feature at all.
- Do not make the Duress Password's existence itself a secret the app
  advertises loudly in a way that undermines its purpose (e.g. don't name
  a UI element "Duress Password" directly on the unlock screen — keep
  labeling for this feature confined to the opt-in setup flow within
  Settings, not the login/unlock screen itself).

## Rules of engagement
- Vault Alpha and Vault Beta must use fully independent encryption keys
  and salts — no shared derivation path that could let compromise of one
  reveal anything about the other.
- The timing and UI of a Duress Password unlock must be indistinguishable
  from a normal Master Password unlock (same loading states, same
  transition animation) — any observable difference undermines the
  feature's purpose.
- Never implement this such that failing to enter either the real Master
  Password or the Duress Password correctly reveals which one was
  "closer" — both wrong attempts must look identical from the outside.
- Write tests for: Duress Password opens only Vault Beta and never leaks
  Vault Alpha's existence/content, the native wipe hook fires reliably on
  Duress Password match, and Vault Alpha's actual encrypted data is
  provably untouched after a duress trigger (only its quick-unlock caches
  are cleared).

## Output location
`core/vault/dual_vault_manager.dart` for the database-selection logic,
`core/platform/duress_wipe_hook.dart` for the native biometric/hardware-key
invalidation call (builds on `native-secure-storage`), and
`app/lib/features/settings/duress_setup_screen.dart` for the opt-in setup
flow.
