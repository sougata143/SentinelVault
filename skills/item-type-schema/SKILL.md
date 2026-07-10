---
name: item-type-schema
description: Use when implementing or modifying the vault item data model — adding new item types (Login, Credit Card, Identity, Secure Note, Bank Account, Password), custom fields, or the add/edit item forms and type picker UI.
---

# Skill: Item Type Schema

## Objective
Implement the multi-item-type vault model exactly as defined in
`docs/ITEM_SCHEMA_AND_UX.md` section 2 — a shared envelope with a
type-specific `fields` object, so the local encrypted store doesn't need a
separate table per item type.

## Rules of engagement
- Every field that holds a secret (password, card number, CVV, PIN,
  account/routing number, OTP secret, and any `custom_fields` entry marked
  `concealed: true`) must be encrypted individually under the Vault Key —
  same code path as any other vault field, no exceptions for "new" item
  types.
- The add/edit UI must show a **type picker** before the form (per
  `vault-ui-navigation` skill), then only the fields relevant to that type
  — never one form with all possible fields visible at once.
- Concealed fields need a reveal toggle and a copy-to-clipboard action; the
  clipboard must auto-clear after a short timeout (~30–60s).
- When adding a new item type beyond the initial six, follow the same
  pattern: define its `fields` shape in this skill's reference schema, add
  a migration if using a versioned local schema, and add it to the type
  picker — don't special-case storage logic per type.

## Output location
Schema/model: `core/models/vault_item.dart`. Add/edit forms and type
picker: `app/lib/features/vault/item_forms/`.
