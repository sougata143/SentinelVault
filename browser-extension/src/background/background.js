// Background service worker for SentinelVault Extension

let lastCapturedCredential = null;

chrome.runtime.onMessage.addListener((request, sender, sendResponse) => {
  if (request.action === "captured_credential") {
    lastCapturedCredential = {
      origin: request.origin,
      username: request.username,
      password: request.password
    };
    sendResponse({ success: true });
    return;
  }

  if (request.action === "get_captured_credential") {
    sendResponse(lastCapturedCredential);
    return;
  }

  if (request.action === "clear_captured_credential") {
    lastCapturedCredential = null;
    sendResponse({ success: true });
    return;
  }

  if (request.action === "get_status") {
    chrome.runtime.sendNativeMessage("com.example.sentinel_vault", { type: "STATUS" }, (response) => {
      if (chrome.runtime.lastError) {
        sendResponse({ running: false, locked: true, error: chrome.runtime.lastError.message });
      } else {
        sendResponse(response);
      }
    });
    return true; // Keep message channel open for async response
  }

  if (request.action === "get_credentials") {
    const origin = request.origin;
    chrome.runtime.sendNativeMessage("com.example.sentinel_vault", { type: "GET_ITEMS", origin: origin }, (response) => {
      if (chrome.runtime.lastError) {
        sendResponse({ success: false, locked: true, items: [], error: chrome.runtime.lastError.message });
      } else {
        sendResponse(response);
      }
    });
    return true; // Keep message channel open for async response
  }
});
