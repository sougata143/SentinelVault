// Content script for safe autofill and credential capture

// Listens for autofill commands from the extension popup
chrome.runtime.onMessage.addListener((request, sender, sendResponse) => {
  if (request.action === "autofill_credentials") {
    // Security Check: Never fill into cross-origin iframes
    if (window.top !== window.self) {
      sendResponse({ success: false, error: "Blocked: Autofill disabled in iframe contexts" });
      return;
    }

    // Security Check: Verify exact origin match
    const pageOrigin = window.location.origin;
    if (request.origin !== pageOrigin) {
      sendResponse({ success: false, error: "Blocked: Origin mismatch" });
      return;
    }

    const { username, password } = request.credentials;
    const filled = performAutofill(username, password);
    sendResponse({ success: filled });
  }
});

function performAutofill(username, password) {
  const passwordInputs = document.querySelectorAll('input[type="password"]');
  if (passwordInputs.length === 0) return false;

  let usernameInput = null;
  for (const pwdInput of passwordInputs) {
    const form = pwdInput.form;
    if (form) {
      usernameInput = form.querySelector('input[type="text"], input[type="email"], input:not([type])');
    }
    
    if (!usernameInput) {
      const inputs = Array.from(document.querySelectorAll('input'));
      const pwdIndex = inputs.indexOf(pwdInput);
      for (let i = pwdIndex - 1; i >= 0; i--) {
        const type = inputs[i].type;
        if (type === 'text' || type === 'email') {
          usernameInput = inputs[i];
          break;
        }
      }
    }

    if (usernameInput) {
      usernameInput.value = username;
      usernameInput.dispatchEvent(new Event('input', { bubbles: true }));
      usernameInput.dispatchEvent(new Event('change', { bubbles: true }));
    }

    pwdInput.value = password;
    pwdInput.dispatchEvent(new Event('input', { bubbles: true }));
    pwdInput.dispatchEvent(new Event('change', { bubbles: true }));
  }

  return true;
}
