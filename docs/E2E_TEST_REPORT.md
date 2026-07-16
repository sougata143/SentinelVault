# SentinelVault — End-to-End Test Report

**Generated:** 2026-07-16  
**Tester:** Automated browser agent (Antigravity)  
**App URL:** http://localhost:8080 (Flutter web dev server)  
**Backend ports:** auth:3001 sync:3002 security:3003 sharing:3004 db:5432

---

## Test Accounts

| Account | Email | Account Password | Master Password |
|---------|-------|-----------------|-----------------|
| A | `test-a@sentinelvault.local` | `TestAccountPassword123!` | `TestMasterPassword456!` |
| B | `test-b@sentinelvault.local` | `TestAccountPassword123!` | `TestMasterPassword456!` |

> **Resumability note:** If Account A/B UUIDs are populated below, DO NOT re-register — reuse those credentials directly. Jump to the first ⏳ PENDING step.

| | UUID |
|--|------|
| Account A UUID | _(pending)_ |
| Account B UUID | _(pending)_ |

---

## Checklist

### Step 1 — Sign up Account A
**Status:** ⏳ PENDING  
**Verify query:** `SELECT id, username FROM users WHERE username = 'test-a@sentinelvault.local';`  
**Result:** _(pending)_  
**Notes:** _(none)_

---

### Step 2 — Master Password setup for Account A
**Status:** ⏳ PENDING  
**Verify query:** `SELECT "userId", salt IS NOT NULL AS salt_set, "wrappedKey" IS NOT NULL AS key_set FROM vault_keys WHERE "userId" = '<A_UUID>';`  
**Result:** _(pending)_  
**Notes:** _(none)_

---

### Step 3 — Emergency Kit / Shamir recovery setup for Account A
**Status:** ⏳ PENDING  
**Verify query:** `SELECT "recoverySalt" IS NOT NULL AS recovery_salt_set, "recoveryWrappedKey" IS NOT NULL AS recovery_key_set FROM vault_keys WHERE "userId" = '<A_UUID>';`  
**Result:** _(pending)_  
**Notes:** _(none)_

---

### Step 4 — Sign up Account B + Master Password setup
**Status:** ⏳ PENDING  
**Verify query:** `SELECT id, username FROM users WHERE username = 'test-b@sentinelvault.local';`  
**Result:** _(pending)_  
**Notes:** _(none)_

---

### Step 5 — Add four vault items as Account A (Login, Credit Card, Secure Note, Bank Account)
**Status:** ⏳ PENDING  
**Verify query (per item):** `SELECT id, "userId", version, "isDeleted" FROM encrypted_vault_items WHERE "userId" = '<A_UUID>' ORDER BY "updatedAt" DESC LIMIT 1;`  
**Results:**  
- Login: _(pending)_  
- Credit Card: _(pending)_  
- Secure Note: _(pending)_  
- Bank Account: _(pending)_  
**Notes:** _(none)_

---

### Step 6 — Edit one vault item (verify version increment)
**Status:** ⏳ PENDING  
**Verify query:** `SELECT id, version, "updatedAt" FROM encrypted_vault_items WHERE "userId" = '<A_UUID>' ORDER BY "updatedAt" DESC LIMIT 1;`  
**Result:** _(pending)_  
**Notes:** _(none)_

---

### Step 7 — Delete one vault item (verify soft-delete)
**Status:** ⏳ PENDING  
**Verify query:** `SELECT id, "isDeleted" FROM encrypted_vault_items WHERE "userId" = '<A_UUID>' AND "isDeleted" = true;`  
**Result:** _(pending)_  
**Notes:** _(none)_

---

### Step 8 — PQC folder sharing (Account A → Account B)
**Status:** ⏳ PENDING  
**Verify queries:**
```sql
SELECT "userId" FROM key_bundles;
SELECT "folderId", "keyVersion" FROM wrapped_key_versions;
SELECT "recipientUserId", "folderId", "keyVersion", "revokedAt" FROM wrapped_key_recipients;
```
**Result:** _(pending)_  
**Notes:** _(none)_

---

### Step 9 — Account B decrypts shared folder through UI
**Status:** ⏳ PENDING  
**Result:** _(pending)_  
**Notes:** _(none)_

---

### Step 10 — Logout and re-login as Account A (full session boundary test)
**Status:** ⏳ PENDING  
**Verify query:** `SELECT COUNT(*) FROM encrypted_vault_items WHERE "userId" = '<A_UUID>' AND "isDeleted" = false;`  
**Result:** _(pending)_  
**Notes:** _(none)_

---

## Final Summary

_(pending — to be filled after all steps complete)_

| Metric | Value |
|--------|-------|
| Total steps | 10 |
| ✅ Passed | 0 |
| ❌ Failed | 0 |
| ⏳ Pending | 10 |

### Bugs Found

_(none yet)_
