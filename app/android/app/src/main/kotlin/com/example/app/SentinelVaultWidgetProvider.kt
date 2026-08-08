package com.example.app

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.view.View
import android.widget.RemoteViews
import org.json.JSONObject

/**
 * AppWidgetProvider for SentinelVault home-screen TOTP code access widget.
 *
 * Security Invariants:
 * 1. Only displays TOTP data when shared data specifies `lockState: "unlocked"`.
 * 2. When locked or purged, renders a privacy-preserving "🔒 Vault Locked" state.
 * 3. Tapping the widget opens SentinelVault directly to the unlock screen.
 */
class SentinelVaultWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        for (appWidgetId in appWidgetIds) {
            updateAppWidget(context, appWidgetManager, appWidgetId)
        }
    }

    companion object {
        fun updateAppWidget(
            context: Context,
            appWidgetManager: AppWidgetManager,
            appWidgetId: Int
        ) {
            val views = RemoteViews(context.packageName, R.layout.sentinel_vault_widget)

            // Read shared data written by home_widget plugin
            val prefs = context.getSharedPreferences("DATA", Context.MODE_PRIVATE)
            val rawData = prefs.getString("sentinelvault_widget_data", null)

            var isUnlocked = false
            var itemTitle = "SentinelVault"
            var itemIssuer = "TOTP Authenticator"
            var itemAccount = ""
            var itemCode = "------"

            if (!rawData.isNullOrEmpty()) {
                try {
                    val json = JSONObject(rawData)
                    val lockState = json.optString("lockState", "locked")
                    val items = json.optJSONArray("items")

                    if (lockState == "unlocked" && items != null && items.length() > 0) {
                        isUnlocked = true
                        val firstItem = items.getJSONObject(0)
                        itemTitle = firstItem.optString("title", "TOTP Item")
                        itemIssuer = firstItem.optString("issuer", itemTitle)
                        itemAccount = firstItem.optString("account", "")
                        itemCode = firstItem.optString("code", "------")
                    }
                } catch (e: Exception) {
                    isUnlocked = false
                }
            }

            if (isUnlocked) {
                views.setViewVisibility(R.id.widget_unlocked_container, View.VISIBLE)
                views.setViewVisibility(R.id.widget_locked_container, View.GONE)
                views.setTextViewText(R.id.widget_issuer, itemIssuer)
                views.setTextViewText(R.id.widget_account, itemAccount)
                views.setTextViewText(R.id.widget_code, formatTotpCode(itemCode))
            } else {
                views.setViewVisibility(R.id.widget_unlocked_container, View.GONE)
                views.setViewVisibility(R.id.widget_locked_container, View.VISIBLE)
                views.setTextViewText(R.id.widget_locked_title, "🔒 Vault Locked")
                views.setTextViewText(R.id.widget_locked_sub, "Tap to open SentinelVault")
            }

            // Launch main activity on widget tap
            val launchIntent = Intent(context, MainActivity::class.java).apply {
                action = Intent.ACTION_VIEW
                data = Uri.parse("sentinelvault://unlock")
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            }
            val pendingIntent = PendingIntent.getActivity(
                context,
                0,
                launchIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            views.setOnClickPendingIntent(R.id.widget_root, pendingIntent)

            appWidgetManager.updateAppWidget(appWidgetId, views)
        }

        private fun formatTotpCode(code: String): String {
            if (code.length == 6) {
                return "${code.substring(0, 3)} ${code.substring(3)}"
            }
            return code
        }
    }
}
