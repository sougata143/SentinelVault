// Content script for safe autofill, shadow-DOM traversal, custom domain overrides, and credential capture

// Listens for extension popup commands
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
    const domainOverride = request.domainOverride || null;

    const result = performAutofill(username, password, domainOverride);
    sendResponse({ success: result.success, filledUsername: result.filledUsername, filledPassword: result.filledPassword });
    return true;
  }

  if (request.action === "inspect_page_fields") {
    const fields = inspectPageFields();
    sendResponse({ success: true, fields: fields });
    return true;
  }
});

// Recursively inspect DOM and open Shadow DOMs to collect all input elements
function findAllInputs(root = document) {
  const inputs = [];

  function traverse(node) {
    if (!node) return;

    if (node.tagName && node.tagName.toLowerCase() === 'input') {
      inputs.push(node);
    }

    // Traverse shadowRoot if present (open Shadow DOM)
    if (node.shadowRoot) {
      traverse(node.shadowRoot);
    }

    // Traverse child nodes
    const children = node.children || node.childNodes || [];
    for (let i = 0; i < children.length; i++) {
      traverse(children[i]);
    }
  }

  traverse(root);
  return inputs;
}

// Helper heuristic to match password fields (standard & non-standard)
function isPasswordInput(input) {
  if (!input) return false;

  const type = (input.type || '').toLowerCase();
  if (type === 'password') return true;

  const autocomplete = (input.getAttribute('autocomplete') || '').toLowerCase();
  if (autocomplete.includes('password')) return true;

  const attrString = [
    input.id,
    input.name,
    input.getAttribute('aria-label'),
    input.placeholder
  ].filter(Boolean).join(' ').toLowerCase();

  return /pass|pwd|secret|auth_key/.test(attrString);
}

// Helper heuristic to match username/identity fields (standard & non-standard)
function isUsernameInput(input) {
  if (!input) return false;
  if (isPasswordInput(input)) return false;

  const type = (input.type || '').toLowerCase();
  if (type === 'hidden' || type === 'submit' || type === 'button' || type === 'checkbox' || type === 'radio') {
    return false;
  }

  const autocomplete = (input.getAttribute('autocomplete') || '').toLowerCase();
  if (autocomplete.includes('username') || autocomplete.includes('email')) return true;

  if (type === 'text' || type === 'email' || type === 'tel' || !type) {
    const attrString = [
      input.id,
      input.name,
      input.getAttribute('aria-label'),
      input.placeholder
    ].filter(Boolean).join(' ').toLowerCase();

    if (/user|login|email|account|identifier|member/.test(attrString)) {
      return true;
    }
    return true; // Fallback text input
  }

  return false;
}

// Generates a simple CSS selector for a given element
function generateCssSelector(element) {
  if (!element) return '';
  if (element.id) return `#${element.id}`;
  if (element.name) return `input[name="${element.name}"]`;
  if (element.getAttribute('aria-label')) return `input[aria-label="${element.getAttribute('aria-label')}"]`;
  if (element.placeholder) return `input[placeholder="${element.placeholder}"]`;
  return 'input';
}

function performAutofill(username, password, domainOverride) {
  let usernameInput = null;
  let passwordInput = null;

  const allInputs = findAllInputs(document);

  // 1. Try custom domain override selectors if configured
  if (domainOverride) {
    if (domainOverride.usernameSelector) {
      try {
        usernameInput = document.querySelector(domainOverride.usernameSelector);
      } catch (_) {}
    }
    if (domainOverride.passwordSelector) {
      try {
        passwordInput = document.querySelector(domainOverride.passwordSelector);
      } catch (_) {}
    }
  }

  // 2. Fall back to heuristic scanning if custom selectors are not defined or not found
  if (!passwordInput) {
    passwordInput = allInputs.find(isPasswordInput) || null;
  }

  if (!usernameInput) {
    if (passwordInput && passwordInput.form) {
      const formInputs = Array.from(passwordInput.form.querySelectorAll('input'));
      usernameInput = formInputs.find(isUsernameInput) || null;
    }
    if (!usernameInput) {
      usernameInput = allInputs.find(isUsernameInput) || null;
    }
  }

  let filledUsername = false;
  let filledPassword = false;

  if (usernameInput && username) {
    usernameInput.value = username;
    usernameInput.dispatchEvent(new Event('input', { bubbles: true }));
    usernameInput.dispatchEvent(new Event('change', { bubbles: true }));
    filledUsername = true;
  }

  if (passwordInput && password) {
    passwordInput.value = password;
    passwordInput.dispatchEvent(new Event('input', { bubbles: true }));
    passwordInput.dispatchEvent(new Event('change', { bubbles: true }));
    filledPassword = true;
  }

  return {
    success: filledUsername || filledPassword,
    filledUsername: filledUsername,
    filledPassword: filledPassword
  };
}

// Local inspection helper capturing relevant field attributes (zero external transmission)
function inspectPageFields() {
  const inputs = findAllInputs(document);
  return inputs.map((input, index) => {
    return {
      index: index,
      id: input.id || '',
      name: input.name || '',
      type: input.type || 'text',
      autocomplete: input.getAttribute('autocomplete') || '',
      ariaLabel: input.getAttribute('aria-label') || '',
      placeholder: input.placeholder || '',
      selector: generateCssSelector(input),
      isPassword: isPasswordInput(input),
      isUsername: isUsernameInput(input)
    };
  });
}

// Credential Capture: Listen to form submissions and clicks on submit buttons
function captureSubmittedCredentials(container) {
  if (!container) return;

  const allInputs = findAllInputs(container);
  const passwordInput = allInputs.find(isPasswordInput);
  if (!passwordInput) return;

  const password = passwordInput.value;
  if (!password) return;

  const usernameInput = allInputs.find(isUsernameInput);
  const username = usernameInput ? usernameInput.value : '';

  const origin = window.location.origin;

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
