---
name: vault-import-export
description: Use when implementing or modifying vault import (from 1Password, Bitwarden, LastPass, generic CSV) or export (encrypted native backup, or gated plaintext CSV/JSON). This is one of the highest-risk features in the app — read fully before writing any code.
---

# Skill: Vault Import / Export

## Objective
Let users migrate data in and out of the vault without ever creating an
unnecessary plaintext-on-disk exposure window.

## Import — required flow
1. File selection and parsing happen **entirely client-side, in memory**.
   The file is never uploaded to any backend or third-party service.
2. Parse into the normalized item schema from the `item-type-schema` skill.
   Support at minimum: 1Password `.1pux`, Bitwarden `.json`, LastPass
   `.csv`, and a generic CSV mapping wizard for anything else.
3. Show a preview (counts by type, any items that failed to parse) before
   committing anything to storage.
4. On confirm: encrypt each parsed item under the Vault Key immediately and
   write only ciphertext to local storage. The in-memory plaintext
   intermediate representation must be explicitly cleared after use — never
   written to a temp file, cache, or log.
5. Do not retain a copy of the original import file within app storage
   after import completes.

## Export — two tiers, do not blur them together
- **Encrypted native export (`.svault`)**: repackages existing ciphertext
  for backup/device migration. Low friction is fine here — it's still
  encrypted.
- **Plaintext CSV/JSON export**: for migrating to a different password
  manager that requires it. Required guardrails, all mandatory:
  - Re-prompt for the master password immediately before export, even if
    the vault is already unlocked.
  - Show a warning modal listing what's about to happen (file will be
    unencrypted) and safe-handling guidance (delete after use, don't email
    or cloud-sync it) before the user can proceed.
  - Default filename should make the file self-identifying as sensitive,
    e.g. `sentinelvault_export_UNENCRYPTED_<date>.csv`.
  - Record that an export happened (timestamp + item count) in the user's
    local security activity log — never log the exported content itself.

## Rules of engagement
- Never build a code path where an imported or exported file's plaintext
  content could be sent to the AI insights service, analytics, or crash
  reporting.
- Write tests using synthetic (non-real) sample export files for each
  supported source format, checking correct field mapping and that
  unmappable fields are flagged, not silently dropped.
- If asked to add a new import source, follow the same pattern: parse to
  the normalized schema, preview, then encrypt-on-commit — don't create a
  shortcut that writes parsed plaintext to disk "temporarily."

## Output location
Parsers: `core/import/parsers/<source>.dart`. Export logic:
`core/export/`. UI flow (file picker, preview, warnings): `app/lib/
features/vault/import_export/`.
