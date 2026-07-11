package com.example.app

import android.content.Context
import android.content.SharedPreferences
import android.os.Build
import android.os.Bundle
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.security.keystore.KeyInfo
import androidx.annotation.NonNull
import androidx.biometric.BiometricManager
import androidx.biometric.BiometricPrompt
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.SecretKeyFactory
import javax.crypto.spec.GCMParameterSpec
import android.security.keystore.KeyPermanentlyInvalidatedException
import android.content.pm.PackageManager
import java.util.concurrent.Executor

class MainActivity : FlutterFragmentActivity() {
    private val CHANNEL = "com.example.app/secure_storage"

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "isHardwareSecureSupported" -> {
                    result.success(isHardwareSecureSupported())
                }
                "writeBiometricWrappedVaultKey" -> {
                    val payload = call.argument<ByteArray>("payload")
                    if (payload != null) {
                        val success = writeBiometricWrappedVaultKey(payload)
                        result.success(success)
                    } else {
                        result.error("INVALID_ARGUMENT", "Payload was null", null)
                    }
                }
                "readBiometricWrappedVaultKey" -> {
                    readBiometricWrappedVaultKey(result)
                }
                "deleteBiometricWrappedVaultKey" -> {
                    val success = deleteBiometricWrappedVaultKey()
                    result.success(success)
                }
                "wasEnrollmentChanged" -> {
                    result.success(wasEnrollmentChanged())
                }
                "resetEnrollmentStatus" -> {
                    val sharedPrefs = getSharedPreferences("SecureStoragePrefs", Context.MODE_PRIVATE)
                    sharedPrefs.edit().putBoolean("mock_enrollment_changed", false).apply()
                    result.success(null)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    private fun generateKeyStoreKey() {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P &&
                packageManager.hasSystemFeature(PackageManager.FEATURE_STRONGBOX_KEYSTORE)) {
                try {
                    val keyGenerator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
                    val builder = KeyGenParameterSpec.Builder(
                        "biometric_vault_key_wrapping_key",
                        KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT
                    )
                    .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                    .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                    .setKeySize(256)
                    .setUserAuthenticationRequired(true)
                    .setIsStrongBoxBacked(true)
                    
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                        builder.setUserAuthenticationParameters(0, KeyProperties.AUTH_BIOMETRIC_STRONG)
                    }
                    keyGenerator.init(builder.build())
                    keyGenerator.generateKey()
                    return
                } catch (e: Exception) {
                    // Fallback to standard hardware key generation
                }
            }
            
            val keyGenerator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
            val builder = KeyGenParameterSpec.Builder(
                "biometric_vault_key_wrapping_key",
                KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT
            )
            .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
            .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
            .setKeySize(256)
            .setUserAuthenticationRequired(true)
            
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                builder.setUserAuthenticationParameters(0, KeyProperties.AUTH_BIOMETRIC_STRONG)
            }
            keyGenerator.init(builder.build())
            keyGenerator.generateKey()
        } catch (e: Exception) {
            // fail silently
        }
    }

    private fun isHardwareSecureSupported(): Boolean {
        // 1. Check if emulator
        val isEmulator = (Build.BRAND.startsWith("generic") && Build.DEVICE.startsWith("generic"))
                || Build.FINGERPRINT.startsWith("generic")
                || Build.FINGERPRINT.startsWith("unknown")
                || Build.HARDWARE.contains("goldfish")
                || Build.HARDWARE.contains("ranchu")
                || Build.MODEL.contains("google_sdk")
                || Build.MODEL.contains("Emulator")
                || Build.MODEL.contains("Android SDK built for x86")
                || Build.MANUFACTURER.contains("Genymotion")
                || Build.PRODUCT.contains("sdk_google")
                || Build.PRODUCT.contains("google_sdk")
                || Build.PRODUCT.contains("sdk")
                || Build.PRODUCT.contains("sdk_x86")
                || Build.PRODUCT.contains("vbox86p")
                || Build.PRODUCT.contains("emulator")
                || Build.PRODUCT.contains("simulator")

        if (isEmulator) {
            return false
        }

        // 2. Check if strong biometrics are available
        val biometricManager = BiometricManager.from(this)
        val canAuthenticate = biometricManager.canAuthenticate(BiometricManager.Authenticators.BIOMETRIC_STRONG)
        if (canAuthenticate != BiometricManager.BIOMETRIC_SUCCESS) {
            return false
        }

        // 3. Verify key is hardware-backed
        return try {
            val keyStore = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
            if (!keyStore.containsAlias("biometric_vault_key_wrapping_key")) {
                generateKeyStoreKey()
            }
            val secretKey = keyStore.getKey("biometric_vault_key_wrapping_key", null) as? SecretKey
            if (secretKey != null) {
                val keyFactory = SecretKeyFactory.getInstance(secretKey.algorithm, "AndroidKeyStore")
                val keyInfo = keyFactory.getKeySpec(secretKey, KeyInfo::class.java) as KeyInfo
                keyInfo.isInsideSecureHardware
            } else {
                false
            }
        } catch (e: Exception) {
            false
        }
    }

    private fun writeBiometricWrappedVaultKey(payload: ByteArray): Boolean {
        return try {
            val keyStore = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
            
            // Delete old key
            keyStore.deleteEntry("biometric_vault_key_wrapping_key")
            
            // Generate new hardware key
            generateKeyStoreKey()
            
            val secretKey = keyStore.getKey("biometric_vault_key_wrapping_key", null) as SecretKey
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(Cipher.ENCRYPT_MODE, secretKey)
            
            val ciphertext = cipher.doFinal(payload)
            val iv = cipher.iv
            
            val sharedPrefs = getSharedPreferences("SecureStoragePrefs", Context.MODE_PRIVATE)
            sharedPrefs.edit().apply {
                putString("encrypted_vault_key", android.util.Base64.encodeToString(ciphertext, android.util.Base64.DEFAULT))
                putString("encrypted_vault_key_iv", android.util.Base64.encodeToString(iv, android.util.Base64.DEFAULT))
                putBoolean("mock_enrollment_changed", false)
                apply()
            }
            true
        } catch (e: Exception) {
            false
        }
    }

    private fun readBiometricWrappedVaultKey(result: MethodChannel.Result) {
        try {
            val keyStore = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
            val secretKey = keyStore.getKey("biometric_vault_key_wrapping_key", null) as? SecretKey
            if (secretKey == null) {
                result.error("NOT_FOUND", "No biometric key generated", null)
                return
            }
            
            val sharedPrefs = getSharedPreferences("SecureStoragePrefs", Context.MODE_PRIVATE)
            val ivString = sharedPrefs.getString("encrypted_vault_key_iv", null)
            if (ivString == null) {
                result.error("NOT_FOUND", "No IV found", null)
                return
            }
            
            val iv = android.util.Base64.decode(ivString, android.util.Base64.DEFAULT)
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            val spec = GCMParameterSpec(128, iv)
            
            try {
                cipher.init(Cipher.DECRYPT_MODE, secretKey, spec)
            } catch (e: KeyPermanentlyInvalidatedException) {
                // Biometrics changed or enrolled
                sharedPrefs.edit().putBoolean("mock_enrollment_changed", true).apply()
                deleteBiometricWrappedVaultKey()
                result.error("KEY_PERMANENTLY_INVALIDATED", "Biometrics enrollment changed", null)
                return
            }
            
            showBiometricPrompt(cipher, result)
        } catch (e: Exception) {
            result.error("READ_FAILED", e.message, null)
        }
    }

    private fun showBiometricPrompt(cipher: Cipher, result: MethodChannel.Result) {
        val executor = ContextCompat.getMainExecutor(this)
        val biometricPrompt = BiometricPrompt(this, executor, object : BiometricPrompt.AuthenticationCallback() {
            override fun onAuthenticationError(errorCode: Int, errString: CharSequence) {
                super.onAuthenticationError(errorCode, errString)
                result.error("AUTH_ERROR", errString.toString(), null)
            }

            override fun onAuthenticationSucceeded(authResult: BiometricPrompt.AuthenticationResult) {
                super.onAuthenticationSucceeded(authResult)
                val authenticatedCipher = authResult.cryptoObject?.cipher
                if (authenticatedCipher != null) {
                    try {
                        val sharedPrefs = getSharedPreferences("SecureStoragePrefs", Context.MODE_PRIVATE)
                        val ciphertextString = sharedPrefs.getString("encrypted_vault_key", null)
                        if (ciphertextString == null) {
                            result.error("NOT_FOUND", "No cached key found", null)
                            return
                        }
                        val ciphertext = android.util.Base64.decode(ciphertextString, android.util.Base64.DEFAULT)
                        val decrypted = authenticatedCipher.doFinal(ciphertext)
                        result.success(decrypted)
                    } catch (e: Exception) {
                        result.error("DECRYPTION_FAILED", e.message, null)
                    }
                } else {
                    result.error("CIPHER_NULL", "Authenticated cipher was null", null)
                }
            }

            override fun onAuthenticationFailed() {
                super.onAuthenticationFailed()
            }
        })

        val promptInfo = BiometricPrompt.PromptInfo.Builder()
            .setTitle("Unlock SentinelVault")
            .setSubtitle("Confirm your biometrics to unlock the vault")
            .setNegativeButtonText("Cancel")
            .setAllowedAuthenticators(BiometricManager.Authenticators.BIOMETRIC_STRONG)
            .build()

        val cryptoObject = BiometricPrompt.CryptoObject(cipher)
        biometricPrompt.authenticate(promptInfo, cryptoObject)
    }

    private fun deleteBiometricWrappedVaultKey(): Boolean {
        return try {
            val keyStore = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
            keyStore.deleteEntry("biometric_vault_key_wrapping_key")
            
            val sharedPrefs = getSharedPreferences("SecureStoragePrefs", Context.MODE_PRIVATE)
            sharedPrefs.edit().apply {
                remove("encrypted_vault_key")
                remove("encrypted_vault_key_iv")
                apply()
            }
            true
        } catch (e: Exception) {
            false
        }
    }

    private fun wasEnrollmentChanged(): Boolean {
        val sharedPrefs = getSharedPreferences("SecureStoragePrefs", Context.MODE_PRIVATE)
        if (sharedPrefs.getBoolean("mock_enrollment_changed", false)) {
            return true
        }
        
        return try {
            val keyStore = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
            val secretKey = keyStore.getKey("biometric_vault_key_wrapping_key", null) as? SecretKey ?: return false
            val ivString = sharedPrefs.getString("encrypted_vault_key_iv", null) ?: return false
            val iv = android.util.Base64.decode(ivString, android.util.Base64.DEFAULT)
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            val spec = GCMParameterSpec(128, iv)
            cipher.init(Cipher.DECRYPT_MODE, secretKey, spec)
            false
        } catch (e: KeyPermanentlyInvalidatedException) {
            sharedPrefs.edit().putBoolean("mock_enrollment_changed", true).apply()
            deleteBiometricWrappedVaultKey()
            true
        } catch (e: Exception) {
            false
        }
    }
}
