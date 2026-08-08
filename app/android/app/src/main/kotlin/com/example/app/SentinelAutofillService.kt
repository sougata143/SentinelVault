package com.example.app

import android.app.assist.AssistStructure
import android.content.Context
import android.os.Build
import android.os.CancellationSignal
import android.service.autofill.AutofillService
import android.service.autofill.Dataset
import android.service.autofill.FillCallback
import android.service.autofill.FillRequest
import android.service.autofill.FillResponse
import android.service.autofill.SaveCallback
import android.service.autofill.SaveRequest
import android.view.autofill.AutofillValue
import android.widget.RemoteViews
import androidx.annotation.RequiresApi
import org.json.JSONArray
import org.json.JSONObject

@RequiresApi(Build.VERSION_CODES.O)
class SentinelAutofillService : AutofillService() {

    override fun onFillRequest(
        request: FillRequest,
        cancellationSignal: CancellationSignal,
        callback: FillCallback
    ) {
        val contexts = request.fillContexts
        if (contexts.isEmpty()) {
            callback.onSuccess(null)
            return
        }

        val latestContext = contexts[contexts.size - 1]
        val structure = latestContext.structure

        // Parse target package name and web domain from AssistStructure
        var targetPackageName: String? = null
        var targetWebDomain: String? = null

        val nodeInfo = parseAssistStructure(structure)
        if (nodeInfo.packageName != null) targetPackageName = nodeInfo.packageName
        if (nodeInfo.webDomain != null) targetWebDomain = nodeInfo.webDomain

        // Read cached encrypted vault credentials from shared preferences
        val prefs = getSharedPreferences("sentinel_autofill_vault_cache", Context.MODE_PRIVATE)
        val credentialsJsonStr = prefs.getString("cached_vault_items", "[]") ?: "[]"
        val credentialsArray = try { JSONArray(credentialsJsonStr) } catch (e: Exception) { JSONArray() }

        if (credentialsArray.length() == 0 || (nodeInfo.usernameId == null && nodeInfo.passwordId == null)) {
            callback.onSuccess(null)
            return
        }

        val fillResponseBuilder = FillResponse.Builder()

        for (i in 0 until credentialsArray.length()) {
            val item = credentialsArray.getJSONObject(i)
            val title = item.optString("title", "SentinelVault Item")
            val username = item.optString("username", "")
            val password = item.optString("password", "")
            val itemDomain = item.optString("domain", "")
            val itemPackage = item.optString("package", "")

            // Match target package name or domain
            val matchesDomain = targetWebDomain != null && itemDomain.isNotEmpty() && targetWebDomain.contains(itemDomain)
            val matchesPackage = targetPackageName != null && itemPackage.isNotEmpty() && targetPackageName == itemPackage
            val isGenericMatch = itemDomain.isEmpty() && itemPackage.isEmpty()

            if (matchesDomain || matchesPackage || isGenericMatch) {
                val presentation = RemoteViews(packageName, android.R.layout.simple_list_item_1)
                presentation.setTextViewText(android.R.id.text1, "SentinelVault: $title ($username)")

                val datasetBuilder = Dataset.Builder()

                if (nodeInfo.usernameId != null && username.isNotEmpty()) {
                    datasetBuilder.setValue(nodeInfo.usernameId, AutofillValue.forText(username), presentation)
                }

                if (nodeInfo.passwordId != null && password.isNotEmpty()) {
                    datasetBuilder.setValue(nodeInfo.passwordId, AutofillValue.forText(password), presentation)
                }

                fillResponseBuilder.addDataset(datasetBuilder.build())
            }
        }

        val fillResponse = fillResponseBuilder.build()
        callback.onSuccess(fillResponse)
    }

    override fun onSaveRequest(request: SaveRequest, callback: SaveCallback) {
        // Save request handled by main app interface
        callback.onSuccess()
    }

    private data class ParsedNodeInfo(
        var packageName: String? = null,
        var webDomain: String? = null,
        var usernameId: android.view.autofill.AutofillId? = null,
        var passwordId: android.view.autofill.AutofillId? = null
    )

    private fun parseAssistStructure(structure: AssistStructure): ParsedNodeInfo {
        val info = ParsedNodeInfo()
        val nodesCount = structure.windowNodeCount
        for (i in 0 until nodesCount) {
            val windowNode = structure.getWindowNodeAt(i)
            val rootNode = windowNode.rootViewNode
            info.packageName = rootNode.idPackage
            traverseNode(rootNode, info)
        }
        return info
    }

    private fun traverseNode(node: AssistStructure.ViewNode, info: ParsedNodeInfo) {
        if (node.webDomain != null) {
            info.webDomain = node.webDomain
        }

        val autofillHints = node.autofillHints
        val hintString = autofillHints?.joinToString(" ")?.lowercase() ?: ""
        val idEntry = (node.idEntry ?: "").lowercase()
        val text = (node.text ?: "").toString().lowercase()

        if (node.autofillType == android.view.View.AUTOFILL_TYPE_TEXT) {
            if (hintString.contains("password") || idEntry.contains("pass") || idEntry.contains("pwd")) {
                info.passwordId = node.autofillId
            } else if (hintString.contains("username") || hintString.contains("email") || idEntry.contains("user") || idEntry.contains("email")) {
                info.usernameId = node.autofillId
            }
        }

        for (i in 0 until node.childCount) {
            traverseNode(node.getChildAt(i), info)
        }
    }
}
