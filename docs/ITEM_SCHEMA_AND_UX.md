# SentinelVault — Item Schema & UX Addendum
### Extends docs/ARCHITECTURE.md with multi-item-type vault, 1Password-style UX, and import/export

---

## 1. Navigation structure

Two primary tabs, plus settings — deliberately minimal, mirroring the
"vault vs. everything else" split you asked for:

```
┌───────────────────────────────────────────────────────────┐
│  SentinelVault                                    [⚙ Settings] │
├───────────────┬─────────────────────────────────────────────┤
│  🔒 Vault       │  🛡 Security Center                          │
├───────────────┴─────────────────────────────────────────────┤
│                                                               │
│  VAULT TAB:                        SECURITY CENTER TAB:      │
│  ┌─────────────┬────────────┐      ┌──────────────────────┐  │
│  │ Sidebar      │ Item list  │      │ Password Health score │  │
│  │ - All Items  │ (search,   │      │ (weak/reused/old/     │  │
│  │ - Logins     │  filter,   │      │  breached counts)      │  │
│  │ - Cards      │  sort)     │      ├──────────────────────┤  │
│  │ - Identities │            │      │ URL Scanner            │  │
│  │ - Secure     │ [+ Add ▾]  │      │ Email Scanner          │  │
│  │   Notes      │ [Import]   │      │ File Scanner           │  │
│  │ - Bank Accts │ [Export]   │      │ Dark-Web Monitor        │  │
│  │ - Tags       │            │      │  (breach alerts feed)   │  │
│  │ - Favorites  │ Item detail│      └──────────────────────┘  │
│  │ - Trash      │ pane →     │                                │
│  └─────────────┴────────────┘                                 │
└───────────────────────────────────────────────────────────────┘
```

- **Vault tab** = the password-manager core: item list, add/edit, import,
  export.
- **Security Center tab** = everything from Phase 5 of the original build
  guide (password strength, URL/email/file scanners, breach monitor),
  surfaced as one dashboard rather than scattered entry points.
- Item detail view opens in a side panel (desktop/web) or full screen
  (mobile), with concealed fields (passwords, card numbers, SSNs) hidden
  behind a reveal toggle and copy-to-clipboard buttons that auto-clear the
  clipboard after ~30–60 seconds.

**On visual identity**: borrow 1Password's *UX conventions* (sidebar +
list + detail pane, concealed-field reveal icons, tag-based organization)
freely — these are common interaction patterns, not protected IP. Don't
copy their actual logo, icon set, exact color values, or brand marks;
build an original visual identity (your own palette, iconography, and
type scale) on top of the same conventions.

---

## 2. Item type schema

All item types share a common envelope; type-specific fields live in a
`fields` object so the local DB schema doesn't need per-type tables.

```json
{
  "id": "uuid",
  "type": "login | credit_card | identity | secure_note | bank_account | password",
  "title": "string",
  "tags": ["string"],
  "favorite": false,
  "vault_id": "uuid",
  "created_at": "iso8601",
  "updated_at": "iso8601",
  "fields": { /* type-specific, see below */ },
  "custom_fields": [
    { "label": "string", "value": "string", "concealed": false, "type": "text|concealed|url|date|otp" }
  ],
  "notes": "string (encrypted like everything else)"
}
```

### Login
```json
{
  "username": "string",
  "password": "string",
  "urls": ["string"],           // one or more, first is "primary"
  "otp_secret": "string|null",  // TOTP seed, rendered as live 6-digit code
  "password_history": [ { "value": "string", "changed_at": "iso8601" } ]
}
```

### Credit Card
```json
{
  "cardholder_name": "string",
  "card_number": "string",
  "brand": "visa|mastercard|amex|discover|other",
  "expiry_month": "int", "expiry_year": "int",
  "cvv": "string",
  "pin": "string|null",
  "billing_address_ref": "identity_id|null"
}
```

### Identity
```json
{
  "first_name": "string", "last_name": "string",
  "birthdate": "date|null",
  "gender": "string|null",
  "address": { "street": "string", "city": "string", "state": "string",
               "zip": "string", "country": "string" },
  "emails": ["string"], "phone_numbers": ["string"],
  "company": "string|null", "job_title": "string|null",
  "website": "string|null"
}
```

### Secure Note
```json
{ "content": "string" }   // freeform, all in `notes`-style encrypted field
```

### Bank Account
```json
{
  "bank_name": "string", "account_type": "checking|savings|other",
  "account_number": "string", "routing_number": "string",
  "iban": "string|null", "swift": "string|null"
}
```

### Standalone Password
```json
{ "password": "string" }   // for a password with no associated login/site
```

Every field marked as holding a secret (`password`, `card_number`, `cvv`,
`pin`, `account_number`, `otp_secret`, any `custom_fields` entry with
`concealed: true`) is encrypted individually under the Vault Key exactly
like any other vault item field — there is no separate "less secure" path
for these just because they're a new item type.

---

## 3. Add/Edit item UX requirements

- A "+" button opens a **type picker** (Login, Credit Card, Identity,
  Secure Note, Bank Account, Password) before showing the form — not one
  giant form with irrelevant fields.
- Login form fields, in this order: Title, Username, Password (with
  generator button + strength meter live from the
  `password-strength-analysis` skill), Website(s) (add multiple), One-Time
  Password (scan QR or paste secret), Tags, Favorite toggle, Notes, then a
  "+ Add custom field" affordance for anything not covered (text or
  concealed).
- Every concealed field gets a reveal (eye icon) and copy button; never
  show a secret in plaintext by default.
- Autofill/QR scan for OTP setup on mobile; paste-based on web.

---

## 4. Import

### Supported source formats (Phase 1 scope)
- 1Password `.1pux` export
- Bitwarden `.json` export
- LastPass `.csv` export
- Generic CSV with a column-mapping step (covers Chrome/Firefox/Edge saved
  password exports and anything else)

### Required flow
1. User selects a file **entirely client-side** — the file is never
   uploaded anywhere; parsing happens locally in `core/`.
2. Parse into a normalized intermediate representation matching the item
   schema above (map source-specific fields, e.g. Bitwarden's `login.uris`
   → our `urls`, or drop/flag fields with no equivalent).
3. Show a **preview screen**: item count, how many of each type, and any
   items that failed to parse — before committing anything.
4. On confirm, each parsed item is immediately encrypted under the Vault
   Key and written to local storage — the plaintext parsed representation
   must be held only in memory and explicitly zeroed/dropped once encrypted,
   never written to a temp file or logged.
5. Delete/dismiss the source file reference after import; never retain a
   copy of the original export file within the app's storage.

---

## 5. Export

### Two tiers, deliberately different friction levels

**Encrypted native export (low friction)** — a `.svault` file containing
the same ciphertext already stored locally (re-wrapped for portability),
usable for backup or migrating between your own devices. Safe to produce
without extra warnings since it's still encrypted.

**Plaintext CSV/JSON export (high friction, explicit opt-in)** — for
migrating to another password manager that needs a specific format. This
is the single riskiest feature in the whole app (a plaintext file
containing every password can end up in Downloads, email, or cloud sync
folders). Required guardrails:
- Require the user to re-enter their master password immediately before
  export (not just "already unlocked" state).
- Show an explicit warning modal explaining the file will be unencrypted
  and listing safe-handling steps (delete after use, don't email it).
- Default the save location to a clearly-named file
  (`sentinelvault_export_UNENCRYPTED_<date>.csv`) so it's recognizable if
  found later.
- Log that an export occurred (timestamp, item count) for the user's own
  security activity view — but never log the exported content.

---

## 6. Security Center dashboard (ties Phase 5 modules together)

- **Password Health score**: aggregate of all Login/Password items run
  through `password-strength-analysis`, plus reused-password detection
  (compare Vault-Key-decrypted values locally, never send full password
  sets anywhere) and stale-password age.
- **Breach feed**: chronological list from `dark-web-monitor` findings.
- **Quick actions**: "Check this URL", "Check this email", "Scan this
  file" entry points feeding the respective Phase 5 modules.
- **AI digest**: a periodic (e.g. weekly) plain-English summary generated
  via `ai-insights-generator` from aggregate structured stats only
  (counts/scores) — never raw vault content.
