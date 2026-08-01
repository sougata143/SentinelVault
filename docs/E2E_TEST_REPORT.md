# SentinelVault — End-to-End Test Report

**Generated:** 2026-08-01  
**Tester:** Automated browser agent (Antigravity)  
**App URL:** http://localhost:8080 (Flutter web dev server)  
**Backend ports:** auth:3001 sync:3002 security:3003 sharing:3004 db:5432

---

## Test Accounts

| Account | Email                        | Account Password          | Master Password          |
|---------|------------------------------|---------------------------|--------------------------|
| A       | `test-a@gmail.com` | `TestAccountPassword123!` | `TestMasterPassword456!` |
| B       | `test-b@gmail.com` | `TestAccountPassword123!` | `TestMasterPassword456!` |

> **Resumability note:** Account A/B UUIDs will be populated below upon signup. DO NOT re-register if UUIDs are present — reuse these credentials directly.

| | UUID |
|---|------|
| Account A UUID | `8e96b1aa-1986-4e20-b9c4-cb50ec763ccd` |
| Account B UUID | `4c2ef4dc-b634-4b7c-a13d-4494347d5688` |

---

## Checklist

### Step 1 — Sign up Account A
**Status:** ✅ PASSED  
**Verify query:** `SELECT id, username FROM users WHERE username = 'test-a@gmail.com';`  
**Result:**
```
                  id                  |     username     
--------------------------------------+------------------
 8e96b1aa-1986-4e20-b9c4-cb50ec763ccd | test-a@gmail.com
(1 row)
```
**Notes:** User `test-a@gmail.com` successfully registered via UI. Account A UUID set to `8e96b1aa-1986-4e20-b9c4-cb50ec763ccd`.

---

### Step 2 — Master Password setup for Account A
**Status:** ✅ PASSED  
**Verify query:** `SELECT "userId", salt IS NOT NULL AS salt_set, "wrappedKey" IS NOT NULL AS key_set FROM vault_keys WHERE "userId" = '8e96b1aa-1986-4e20-b9c4-cb50ec763ccd';`  
**Result:**
```
                userId                | salt_set | key_set 
--------------------------------------+----------+---------
 8e96b1aa-1986-4e20-b9c4-cb50ec763ccd | t        | t
(1 row)
```
**Notes:** Salt (`134fc8...`) and wrapped key (`7e2d13...`) successfully populated for Account A.

---

### Step 3 — Emergency Kit / Shamir recovery setup for Account A
**Status:** ✅ PASSED  
**Verify query:** `SELECT "recoverySalt" IS NOT NULL AS recovery_salt_set, "recoveryWrappedKey" IS NOT NULL AS recovery_key_set FROM vault_keys WHERE "userId" = '8e96b1aa-1986-4e20-b9c4-cb50ec763ccd';`  
**Result:**
```
 recovery_salt_set | recovery_key_set 
-------------------+------------------
 t                 | t
(1 row)
```
**Notes:** Emergency recovery salt (`1b49aa...`) and recovery wrapped key (`bd1056...`) successfully populated.

---

### Step 4 — Sign up Account B + Master Password setup
**Status:** ✅ PASSED  
**Verify query:** `SELECT id, username FROM users WHERE username = 'test-b@gmail.com';`  
**Result:**
```
                  id                  |     username     
--------------------------------------+------------------
 4c2ef4dc-b634-4b7c-a13d-4494347d5688 | test-b@gmail.com
(1 row)
```
**Notes:** User `test-b@gmail.com` successfully registered via UI. Vault key salt (`5e7568...`) and wrapped key (`d32f03...`) populated in `vault_keys`. Account B UUID set to `4c2ef4dc-b634-4b7c-a13d-4494347d5688`.

---

### Step 5 — Add four vault items as Account A (Login, Credit Card, Secure Note, Bank Account)
**Status:** ✅ PASSED  
**Verify query:** `SELECT id, "userId", version, "isDeleted" FROM encrypted_vault_items WHERE "userId" = '8e96b1aa-1986-4e20-b9c4-cb50ec763ccd' ORDER BY "updatedAt" ASC;`  
**Result:**
- Item 1 (Login): `f4c63cd8-28d9-4b9e-a7f9-b5b6fb7e7b1c` (version=1, isDeleted=false)
- Item 2 (Credit Card): `828b4922-6a09-4377-ae01-9d8d21f9644b` (version=1, isDeleted=false)
- Item 3 (Secure Note): `d40c126d-19b5-431b-9708-65550452a7f3` (version=1, isDeleted=false)
- Item 4 (Bank Account): `74645698-90bb-4d2c-9199-97cd19a0bc85` (version=1, isDeleted=false)
```
                  id                  | version | isDeleted |                userId                
--------------------------------------+---------+-----------+--------------------------------------
 f4c63cd8-28d9-4b9e-a7f9-b5b6fb7e7b1c |       1 | f         | 8e96b1aa-1986-4e20-b9c4-cb50ec763ccd
 828b4922-6a09-4377-ae01-9d8d21f9644b |       1 | f         | 8e96b1aa-1986-4e20-b9c4-cb50ec763ccd
 d40c126d-19b5-431b-9708-65550452a7f3 |       1 | f         | 8e96b1aa-1986-4e20-b9c4-cb50ec763ccd
 74645698-90bb-4d2c-9199-97cd19a0bc85 |       1 | f         | 8e96b1aa-1986-4e20-b9c4-cb50ec763ccd
(4 rows)
```
**Notes:** 4 encrypted vault items of distinct types added successfully under Account A.

---

### Step 6 — Edit one vault item (verify version increment)
**Status:** ✅ PASSED  
**Verify query:** `SELECT id, version, "isDeleted", "updatedAt" FROM encrypted_vault_items WHERE id = '828b4922-6a09-4377-ae01-9d8d21f9644b';`  
**Result:**
```
                  id                  | version | isDeleted |        updatedAt        
--------------------------------------+---------+-----------+-------------------------
 828b4922-6a09-4377-ae01-9d8d21f9644b |       2 | f         | 2026-07-31 20:19:58.231
(1 row)
```
**Notes:** Version incremented from 1 to 2 and `updatedAt` timestamp updated upon edit in UI.

---

### Step 7 — Delete one vault item (verify soft-delete)
**Status:** ✅ PASSED  
**Verify query:** `SELECT id, version, "isDeleted", "updatedAt" FROM encrypted_vault_items WHERE id = 'f4c63cd8-28d9-4b9e-a7f9-b5b6fb7e7b1c';`  
**Result:**
```
                  id                  | version | isDeleted |       updatedAt       
--------------------------------------+---------+-----------+-----------------------
 f4c63cd8-28d9-4b9e-a7f9-b5b6fb7e7b1c |       2 | t         | 2026-07-31 20:20:05.4
(1 row)
```
**Notes:** Row remains present in `encrypted_vault_items` table with `isDeleted = true` (soft delete).

---

### Step 8 — PQC folder sharing (Account A → Account B)
**Status:** ❌ FAILED  
**Verify queries:**
```sql
SELECT * FROM key_bundles;
SELECT * FROM wrapped_key_versions;
SELECT * FROM wrapped_key_recipients;
```
**Result:**
```
 userId | x25519PublicKey | ed25519PublicKey | mlkemEncapsulationKey | mldsaVerifyingKey | keyFingerprint | publishedAt | updatedAt 
--------+-----------------+------------------+-----------------------+-------------------+----------------+-------------+-----------
(0 rows)

 folderId | keyVersion | publishedAt 
----------+------------+-------------
(0 rows)

 recipientUserId | folderId | keyVersion | ephemeralX25519PublicKey | mlkemCiphertext | aesNonce | wrappedFolderKey | revokedAt | createdAt 
-----------------+----------+------------+--------------------------+-----------------+----------+------------------+-----------+-----------
(0 rows)
```
**Error Text:** `UnimplementedError` thrown in Flutter Web UI.  
**Root Cause:** In [`core/lib/src/crypto/native_crypto_bridge_web.dart:302-331`](file:///c:/Antigravity%20IDE%20Workspace/SentinelVault/core/lib/src/crypto/native_crypto_bridge_web.dart#L302-L331), PQC methods (`pqcGenerateKeypairs`, `pqcHybridWrap`, `pqcHybridUnwrap`, `pqcSignInvitation`, `pqcVerifyInvitation`) are stubbed with `=> throw UnimplementedError()`.

---

### Step 9 — Account B decrypts shared folder through UI
**Status:** ❌ FAILED  
**Verify UI:** Confirm shared folder/item is visible and decryptable in UI.  
**Result:**
```
❌ Blocked by Step 8 failure: PQC folder key wrapping/invitation was not generated due to UnimplementedError in Web bridge.
```

---

### Step 10 — Logout and re-login as Account A (full session boundary test)
**Status:** ❌ FAILED  
**Verify query:** `SELECT COUNT(*) FROM encrypted_vault_items WHERE "userId" = '8e96b1aa-1986-4e20-b9c4-cb50ec763ccd';`  
**Result:**
```
                  id                  | version | isDeleted |                userId                
--------------------------------------+---------+-----------+--------------------------------------
 d40c126d-19b5-431b-9708-65550452a7f3 |       1 | f         | 8e96b1aa-1986-4e20-b9c4-cb50ec763ccd
 74645698-90bb-4d2c-9199-97cd19a0bc85 |       1 | f         | 8e96b1aa-1986-4e20-b9c4-cb50ec763ccd
 828b4922-6a09-4377-ae01-9d8d21f9644b |       2 | f         | 8e96b1aa-1986-4e20-b9c4-cb50ec763ccd
 f4c63cd8-28d9-4b9e-a7f9-b5b6fb7e7b1c |       2 | t         | 8e96b1aa-1986-4e20-b9c4-cb50ec763ccd
(4 rows in PostgreSQL database)
```
**Error Text:** Items missing from UI after unlock.  
**Root Cause:** Upon re-logging in and unlocking the vault, the local `VaultDatabase` is initialized empty and `HttpSyncApiClient.pull()` is not automatically triggered to sync items down from the backend `sync-api` service, resulting in an empty vault UI display despite the items existing in PostgreSQL.

---

## Final Summary

| Metric | Value |
|--------|-------|
| Total steps | 10 |
| ✅ Passed | 7 |
| ❌ Failed | 3 |
| ⏳ Pending | 0 |

### Bugs Found

1. **Unimplemented PQC Crypto Methods on Web Platform (`native_crypto_bridge_web.dart`)**:
   - **Exact Reproduction Steps**:
     1. Log into SentinelVault Web application at `http://localhost:8080` as Account A.
     2. Attempt to create/share a folder or perform PQC key bundle setup.
     3. The UI encounters an `UnimplementedError` exception.
   - **Exact Error Text**: `UnimplementedError`
   - **Root Cause & Code Location**: In [`core/lib/src/crypto/native_crypto_bridge_web.dart:302-331`](file:///c:/Antigravity%20IDE%20Workspace/SentinelVault/core/lib/src/crypto/native_crypto_bridge_web.dart#L302-L331), the PQC cryptographic functions (`pqcGenerateKeypairs`, `pqcHybridWrap`, `pqcHybridUnwrap`, `pqcSignInvitation`, `pqcVerifyInvitation`) are unimplemented and throw `UnimplementedError()`.
   - **Database Query Evidence**:
     ```sql
     SELECT COUNT(*) FROM key_bundles;            -- Returns 0
     SELECT COUNT(*) FROM wrapped_key_recipients; -- Returns 0
     ```

2. **Missing Remote Vault Sync Pull on Session Login/Unlock (`vault_tab.dart`)**:
   - **Exact Reproduction Steps**:
     1. Log in as Account A (`test-a@gmail.com`) and add items to the vault.
     2. Log out of Account A.
     3. Log back in as Account A and enter the correct Master Password (`TestMasterPassword456!`) to unlock.
     4. The vault dashboard opens but displays 0 items.
   - **Exact Error Text**: Vault items fail to load on fresh session login/unlock.
   - **Root Cause & Code Location**: In [`app/lib/features/vault/vault_tab.dart:42-69`](file:///c:/Antigravity%20IDE%20Workspace/SentinelVault/app/lib/features/vault/vault_tab.dart#L42-L69), `_loadItems()` only reads from local `widget.db.getAllItems()` without triggering an initial `syncClient.pull()` from `sync-api` (`encrypted_vault_items`) to populate the local DB state.
   - **Database Query Evidence**:
     ```sql
     SELECT id, version, "isDeleted", "userId" FROM encrypted_vault_items WHERE "userId" = '8e96b1aa-1986-4e20-b9c4-cb50ec763ccd';
     -- Returns 4 rows in PostgreSQL, but 0 items render in UI after re-login.
     ```
