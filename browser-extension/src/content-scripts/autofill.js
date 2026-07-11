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

// Credential Capture: Listen to form submissions and clicks on submit buttons
function captureSubmittedCredentials(container) {
  if (!container) return;

  const passwordInput = container.querySelector('input[type="password"]');
  if (!passwordInput) return;

  const password = passwordInput.value;
  if (!password) return;

  const usernameInput = container.querySelector('input[type="text"], input[type="email"], input:not([type])');
  const username = usernameInput ? usernameInput.value : '';

  // Get current origin
  const origin = window.location.origin;

  // Send captured credentials to background via extension messaging API (isolated from page JS context)
  chrome.runtime.sendMessage({
    action: "captured_credential",
    origin: origin,
    username: username,
    password: password
  });
}

document.addEventListener('submit', (event) => {
  captureSubmittedCredentials(event.target);
});

document.addEventListener('click', (event) => {
  const button = event.target.closest('button, input[type="submit"]');
  if (!button) return;

  const form = button.form || button.closest('form');
  if (form) {
    captureSubmittedCredentials(form);
  } else {
    captureSubmittedCredentials(button.parentElement);
  }
});

