---
name: vault-ui-navigation
description: Use when implementing or modifying app navigation/IA — the Vault tab vs. Security Center tab split, sidebar categories, item list/detail layout, or overall visual design system.
---

# Skill: Vault UI Navigation & Design System

## Objective
Implement the two-tab structure and list/detail interaction pattern defined
in `docs/ITEM_SCHEMA_AND_UX.md` section 1, with an original visual identity
that follows familiar password-manager UX conventions without copying any
specific product's branding.

## Structure to implement
- **Vault tab**: sidebar (All Items, per-type categories, Tags, Favorites,
  Trash) + item list (search, filter, sort) + detail pane. "+ Add" opens
  the type picker from `item-type-schema`. Import/Export entry points live
  here.
- **Security Center tab**: dashboard combining password health score,
  breach feed, and quick-action entry points into the URL/email/file
  scanners built in the original Phase 5 modules.
- Settings reachable separately (not a third main tab) — profile, vaults,
  security settings (MFA, auto-lock timer, clipboard clear timeout),
  about/support.

## Design system rules
- Define an original color palette, type scale, and spacing system in one
  shared theme file/module — don't hardcode colors/sizes per screen.
- Concealed fields (passwords, card numbers, SSNs, etc.) always render
  masked by default with an explicit reveal toggle — never show a secret
  value by default anywhere in the UI, including in list previews.
- Copy-to-clipboard actions on any secret field must trigger an
  auto-clear-clipboard timer (configurable, default ~30–60s) and ideally a
  brief on-screen confirmation ("Copied — clearing in 30s").
- Responsive: sidebar + list + detail as three columns on wide/web
  layouts, collapsing to list → detail navigation on mobile widths.
- Do not reproduce any specific existing product's logo, icon set, or exact
  brand color values — build original assets that follow the same
  structural conventions (sidebar navigation, list/detail pattern,
  reveal-to-view secrets).

## Output location
Navigation shell: `app/lib/app_shell.dart`. Theme/design tokens:
`app/lib/theme/`. Vault tab screens: `app/lib/features/vault/`. Security
Center screens: `app/lib/features/security_center/`.
