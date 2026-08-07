package com.example.app

import android.os.Build
import android.os.CancellationSignal
import android.service.credentials.CallingAppInfo
import android.service.credentials.CredentialProviderService
import android.service.credentials.BeginGetCredentialRequest
import android.service.credentials.BeginGetCredentialResponse
import android.service.credentials.BeginCreateCredentialRequest
import android.service.credentials.BeginCreateCredentialResponse
import android.service.credentials.ClearCredentialStateRequest
import android.service.credentials.CredentialEntry
import android.service.credentials.CreateEntry
import android.outcome.OutcomeReceiver
import androidx.annotation.RequiresApi

/**
 * SentinelVault Android Credential Manager Provider Service (Android 14+ / API 34+).
 * Enables SentinelVault to act as a FIDO2 / WebAuthn platform authenticator and passkey manager.
 */
@RequiresApi(Build.VERSION_CODES.UPSIDE_DOWN_CAKE)
class SentinelCredentialProviderService : CredentialProviderService() {

    override fun onBeginGetCredential(
        request: BeginGetCredentialRequest,
        cancellationSignal: CancellationSignal,
        callback: OutcomeReceiver<BeginGetCredentialResponse, android.credentials.GetCredentialException>
    ) {
        val callingAppInfo: CallingAppInfo? = request.callingAppInfo
        val callingPackage = callingAppInfo?.packageName ?: "unknown"

        val responseBuilder = BeginGetCredentialResponse.Builder()

        for (option in request.beginGetCredentialOptions) {
            if (option.type == "android.credentials.TYPE_PUBLIC_KEY_CREDENTIAL") {
                val candidateData = option.candidateQueryData
                val reqJson = candidateData.getString("requestJson") ?: ""

                // Extract RP ID from query option or package name
                val rpId = extractRpIdFromJson(reqJson, callingPackage)

                // Build candidate credential entries available for this RP
                val entry = CredentialEntry(
                    option.type,
                    android.app.PendingIntent.getActivity(
                        this,
                        0,
                        android.content.Intent(this, MainActivity::class.java).apply {
                            action = "com.example.app.WEBAUTHN_ASSERT"
                            putExtra("rpId", rpId)
                            putExtra("requestJson", reqJson)
                            putExtra("callingPackage", callingPackage)
                        },
                        android.app.PendingIntent.FLAG_MUTABLE or android.app.PendingIntent.FLAG_UPDATE_CURRENT
                    )
                )
                responseBuilder.addCredentialEntry(entry)
            }
        }

        callback.onResult(responseBuilder.build())
    }

    override fun onBeginCreateCredential(
        request: BeginCreateCredentialRequest,
        cancellationSignal: CancellationSignal,
        callback: OutcomeReceiver<BeginCreateCredentialResponse, android.credentials.CreateCredentialException>
    ) {
        val callingAppInfo: CallingAppInfo? = request.callingAppInfo
        val callingPackage = callingAppInfo?.packageName ?: "unknown"

        if (request.type == "android.credentials.TYPE_PUBLIC_KEY_CREDENTIAL") {
            val reqJson = request.credentialData.getString("requestJson") ?: ""
            val rpId = extractRpIdFromJson(reqJson, callingPackage)

            val createEntry = CreateEntry(
                android.app.PendingIntent.getActivity(
                    this,
                    0,
                    android.content.Intent(this, MainActivity::class.java).apply {
                        action = "com.example.app.WEBAUTHN_REGISTER"
                        putExtra("rpId", rpId)
                        putExtra("requestJson", reqJson)
                        putExtra("callingPackage", callingPackage)
                    },
                    android.app.PendingIntent.FLAG_MUTABLE or android.app.PendingIntent.FLAG_UPDATE_CURRENT
                )
            )

            val response = BeginCreateCredentialResponse.Builder()
                .setCreateEntry(createEntry)
                .build()

            callback.onResult(response)
        } else {
            callback.onError(
                android.credentials.CreateCredentialException(
                    android.credentials.CreateCredentialException.TYPE_UNKNOWN,
                    "Unsupported credential type: ${request.type}"
                )
            )
        }
    }

    override fun onClearCredentialState(
        request: ClearCredentialStateRequest,
        cancellationSignal: CancellationSignal,
        callback: OutcomeReceiver<Void?, android.credentials.ClearCredentialException>
    ) {
        // Clear transient passkey session state
        callback.onResult(null)
    }

    private fun extractRpIdFromJson(json: String, fallback: String): String {
        return try {
            val org = org.json.JSONObject(json)
            val rp = org.optJSONObject("rp")
            rp?.optString("id") ?: fallback
        } catch (_: Exception) {
            fallback
        }
    }
}
