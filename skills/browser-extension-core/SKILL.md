---
name: browser-extension-core
description: Use when compiling the shared Dart crypto/vault core to JS/Wasm for browser extension use, or building the Chrome/Firefox/Safari extension itself (autofill, credential capture, native messaging to the main app).
---

# Skill: Browser Extension Core

## Objective
Ship Chrome, Firefox, and Safari extensions that reuse the existing
crypto/vault core rather than reimplementing it, using a **thin-extension,
paired-to-app** architecture by default — the extension does not hold its
own independent copy of the Vault Key.

## Architecture (recommended default)
- The extension's background service worker communicates with the
  already-running native/desktop app via a **native messaging host**
  (Chrome/Firefox Native Messaging API; Safari's equivalent) — it asks
  "is the vault currently unlocked, and if so, give me matching items for
  this origin," rather than performing its own unlock or holding Master
  Key/Vault Key material.
- Only if/when a standalone "extension has its own lock/unlock" mode is
  explicitly wanted later should the compiled Dart-to-JS/Wasm core be used
  to run the full crypto stack inside the extension itself — treat that as
  a separate, later addition, not the initial implementation, since it
  duplicates the highest-risk part of the system into a second execution
  context.
- Compile the shared `core/` package to a JS/Wasm bundle
  (`dart2js` for JS output, or the current Dart-to-Wasm toolchain — verify
  toolchain maturity at implementation time) only for the pieces actually
  needed in the paired mode (e.g. any client-side matching/heuristic logic
  that shouldn't round-trip to the native app for every keystroke) rather
  than the entire crypto core.

## Content-script rules (apply regardless of paired vs. standalone mode)
- Autofill only into a form whose page origin exactly matches the stored
  item's saved origin — no subdomain-wildcard matching by default.
- Never fill credentials into a cross-origin iframe embedded in an
  otherwise-matching page.
- Content scripts run in the isolated content-script world; communicate
  with the extension's background/service worker only via extension
  messaging APIs — never expose vault data to the hosting page's own
  JavaScript via `window.postMessage` or a shared global.
- Credential-capture (detecting a new login being submitted, offering to
  save it) must only read form field values the user is actively
  submitting — never scrape arbitrary page content or other forms on the
  page.
- Manifest V3 (Chrome/Firefox) and Safari Web Extension equivalents: keep
  permissions minimal (host permissions scoped as narrowly as the browser
  allows, not `<all_urls>` by default if a narrower option exists for the
  target use case).

## Rules of engagement
- Never let the extension cache a Master Password or Vault Key on disk
  independent of the native app's own secure storage in paired mode — if
  the native app locks, the extension must reflect locked state
  immediately, not continue serving cached credentials.
- Write tests/manual QA steps for: autofill only matches exact origin,
  cross-origin iframe fill is blocked, and extension reflects a Lock
  triggered from the native app within one interaction (e.g. popup reopen).

## Output location
Compiled core bundle: `browser-extension/core-bundle/` (generated, not
hand-edited). Extension source: `browser-extension/src/` with
`background/`, `content-scripts/`, and `native-messaging/` subfolders.
