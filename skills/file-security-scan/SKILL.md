---
name: file-security-scan
description: Use when building or modifying the file security check feature — local hash/signature checks, VirusTotal hash-reputation lookups, or the opt-in full file upload scan flow.
---

# Skill: File Security Scan

## Objective
Give a fast, privacy-preserving first pass on a file's safety using local
checks and hash-reputation lookups, escalating to a full scan only with
explicit user consent.

## Layer 1 — Local checks (no network)
- Compute SHA-256 of the file.
- Detect mismatched file signature (magic bytes) vs. file extension
  (e.g. an `.pdf` that's actually a PE executable).
- Detect double extensions (`invoice.pdf.exe`).
- Detect macro-enabled Office formats (`.docm`, `.xlsm`) and flag for
  extra scrutiny.

## Layer 2 — Hash reputation (network, hash only)
- Query VirusTotal's file-hash-lookup endpoint with the SHA-256 only — this
  does not require uploading file contents and should be the default path.

## Layer 3 — Full scan (explicit opt-in only)
- Only if Layer 1+2 are inconclusive AND the user explicitly consents,
  upload the file to VirusTotal's file-scan endpoint. Clearly disclose that
  this sends file contents to a third party before doing so.

## Rules of engagement
- Default behavior must stop at Layer 2. Layer 3 requires an explicit,
  per-file user confirmation dialog — never a global "always allow" toggle
  enabled by default.
- Never send file contents to the AI insights layer. Only send:
  `{file_extension, signature_mismatch: bool, macro_detected: bool,
  reputation_verdict}`.
- Handle large files by hashing in streaming chunks, not loading entire
  files into memory.

## Output location
`core/security/file_scanner.dart` (local checks) and
`backend/security-analysis-service/file-reputation/` (VirusTotal client).
