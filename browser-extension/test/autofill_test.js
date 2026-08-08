const fs = require('fs');
const path = require('path');

// 1. Setup Mock DOM environment
global.window = {
  top: {},
  self: {}
};
global.window.top = global.window; // Top level by default

global.location = {
  origin: "https://example.com"
};
global.window.location = global.location;

function createMockInput(attributes = {}) {
  const input = {
    tagName: 'INPUT',
    type: attributes.type || 'text',
    id: attributes.id || '',
    name: attributes.name || '',
    value: attributes.value || '',
    placeholder: attributes.placeholder || '',
    form: attributes.form || null,
    shadowRoot: attributes.shadowRoot || null,
    children: attributes.children || [],
    attributes: attributes.attrs || {},
    getAttribute: (attrName) => attributes.attrs ? attributes.attrs[attrName] : (attributes[attrName] || null),
    dispatchEvent: (event) => {}
  };
  return input;
}

global.document = {
  children: [],
  listeners: {},
  addEventListener: (event, cb) => {
    global.document.listeners[event] = global.document.listeners[event] || [];
    global.document.listeners[event].push(cb);
  },
  dispatchEvent: (event) => {
    if (global.document.listeners[event.type]) {
      global.document.listeners[event.type].forEach(cb => cb(event));
    }
  },
  querySelectorAll: (selector) => {
    return (global.document.children || []).filter(node => {
      if (selector === 'input[type="password"]') return node.type === 'password';
      return node.tagName === 'INPUT';
    });
  },
  querySelector: (selector) => {
    if (!selector) return null;
    return (global.document.children || []).find(node => {
      if (selector.startsWith('#') && node.id === selector.slice(1)) return true;
      if (selector.includes('name="') && node.name === selector.match(/name="([^"]+)"/)[1]) return true;
      return false;
    }) || null;
  }
};

global.Event = class Event {
  constructor(type, options) {
    this.type = type;
    this.options = options;
  }
};

// Mock chrome extension APIs
const chromeListeners = [];
const sentMessages = [];
global.chrome = {
  runtime: {
    onMessage: {
      addListener: (cb) => {
        chromeListeners.push(cb);
      }
    },
    sendMessage: (msg) => {
      sentMessages.push(msg);
    }
  }
};

// 2. Load the content script code
const code = fs.readFileSync(path.join(__dirname, '../src/content-scripts/autofill.js'), 'utf8');
eval(code);

// 3. Define Tests
function assert(condition, message) {
  if (!condition) {
    throw new Error("Assertion Failed: " + message);
  }
}

function runTests() {
  console.log("Running Autofill & Credential Capture Content Script Tests...");

  // Test 1: Autofill blocks if in iframe context
  {
    global.window.self = {}; // window.top !== window.self -> iframe context
    let responseCalled = false;
    chromeListeners[0]({
      action: "autofill_credentials",
      origin: "https://example.com",
      credentials: { username: "user", password: "password" }
    }, {}, (res) => {
      assert(res.success === false, "Autofill should fail in iframe context");
      assert(res.error.includes("iframe contexts"), "Error message should mention iframe context");
      responseCalled = true;
    });
    assert(responseCalled, "Response callback should have been executed");
    console.log("✓ Test 1: Blocked in cross-origin iframe - PASSED");
  }

  // Test 2: Autofill blocks on origin mismatch
  {
    global.window.self = global.window.top; // reset to top level
    global.location.origin = "https://legit.com";
    let responseCalled = false;
    chromeListeners[0]({
      action: "autofill_credentials",
      origin: "https://phishing.com",
      credentials: { username: "user", password: "password" }
    }, {}, (res) => {
      assert(res.success === false, "Autofill should fail on origin mismatch");
      assert(res.error.includes("Origin mismatch"), "Error message should mention origin mismatch");
      responseCalled = true;
    });
    assert(responseCalled, "Response callback should have been executed");
    console.log("✓ Test 2: Scoped to matching origins only - PASSED");
  }

  // Test 3: Standard Form Fixture Detection & Fill
  {
    global.location.origin = "https://example.com";
    const userInput = createMockInput({ id: "username_id", type: "text", name: "user_login" });
    const passInput = createMockInput({ id: "password_id", type: "password", name: "user_pass" });
    global.document.children = [userInput, passInput];

    let responseCalled = false;
    chromeListeners[0]({
      action: "autofill_credentials",
      origin: "https://example.com",
      credentials: { username: "john_doe", password: "SecretPassword123!" }
    }, {}, (res) => {
      assert(res.success === true, "Standard form autofill should succeed");
      assert(userInput.value === "john_doe", "Username value set");
      assert(passInput.value === "SecretPassword123!", "Password value set");
      responseCalled = true;
    });
    assert(responseCalled, "Autofill callback executed");
    console.log("✓ Test 3: Standard Form Fixture - PASSED");
  }

  // Test 4: Shadow DOM Form Fixture Traversal
  {
    const shadowUser = createMockInput({ id: "shadow_user", type: "text", name: "shadow_login" });
    const shadowPass = createMockInput({ id: "shadow_pass", type: "password", name: "shadow_pwd" });

    const shadowRootNode = {
      children: [shadowUser, shadowPass]
    };

    const customWebComponent = {
      tagName: 'MY-LOGIN-WIDGET',
      children: [],
      shadowRoot: shadowRootNode
    };

    global.document.children = [customWebComponent];

    let responseCalled = false;
    chromeListeners[0]({
      action: "autofill_credentials",
      origin: "https://example.com",
      credentials: { username: "shadow_user@domain.com", password: "ShadowPassword123!" }
    }, {}, (res) => {
      assert(res.success === true, "Shadow DOM autofill should penetrate web components");
      assert(shadowUser.value === "shadow_user@domain.com", "Shadow DOM Username value set");
      assert(shadowPass.value === "ShadowPassword123!", "Shadow DOM Password value set");
      responseCalled = true;
    });
    assert(responseCalled, "Shadow DOM callback executed");
    console.log("✓ Test 4: Shadow DOM Form Fixture - PASSED");
  }

  // Test 5: Multi-Step Login Form Fixture (Screen 1 Username Only)
  {
    const emailOnlyInput = createMockInput({ id: "identifier_input", type: "email", name: "email_address" });
    global.document.children = [emailOnlyInput];

    let responseCalled = false;
    chromeListeners[0]({
      action: "autofill_credentials",
      origin: "https://example.com",
      credentials: { username: "step1_user@domain.com", password: "Password123!" }
    }, {}, (res) => {
      assert(res.success === true, "Multi-step login should fill username on step 1 without password");
      assert(res.filledUsername === true, "Username filled on step 1");
      assert(res.filledPassword === false, "Password not filled on step 1");
      assert(emailOnlyInput.value === "step1_user@domain.com", "Username input populated");
      responseCalled = true;
    });
    assert(responseCalled, "Multi-step login callback executed");
    console.log("✓ Test 5: Multi-Step Login Form Fixture - PASSED");
  }

  // Test 6: Non-Standard Attribute & ARIA Label Fixture
  {
    const ariaPassInput = createMockInput({
      id: "custom_sec_field",
      type: "text",
      attrs: { "aria-label": "Enter your Security Password", "autocomplete": "current-password" }
    });
    const ariaUserInput = createMockInput({
      id: "custom_id_field",
      type: "text",
      attrs: { "aria-label": "Account Identifier", "autocomplete": "username" }
    });

    global.document.children = [ariaUserInput, ariaPassInput];

    let responseCalled = false;
    chromeListeners[0]({
      action: "autofill_credentials",
      origin: "https://example.com",
      credentials: { username: "aria_user", password: "AriaPassword123!" }
    }, {}, (res) => {
      assert(res.success === true, "Non-standard ARIA autofill should succeed");
      assert(ariaUserInput.value === "aria_user", "ARIA username set");
      assert(ariaPassInput.value === "AriaPassword123!", "ARIA password set");
      responseCalled = true;
    });
    assert(responseCalled, "ARIA test callback executed");
    console.log("✓ Test 6: Non-Standard ARIA & Attribute Fixture - PASSED");
  }

  // Test 7: Per-Domain Custom Field Mapping Override
  {
    const trickyUser = createMockInput({ id: "tricky_usr_id", name: "foo_user", type: "text" });
    const trickyPass = createMockInput({ id: "tricky_pwd_id", name: "bar_pass", type: "text" });
    global.document.children = [trickyUser, trickyPass];

    const customOverride = {
      usernameSelector: "#tricky_usr_id",
      passwordSelector: "#tricky_pwd_id"
    };

    let responseCalled = false;
    chromeListeners[0]({
      action: "autofill_credentials",
      origin: "https://example.com",
      credentials: { username: "custom_override_user", password: "OverridePassword123!" },
      domainOverride: customOverride
    }, {}, (res) => {
      assert(res.success === true, "Custom domain override autofill should succeed");
      assert(trickyUser.value === "custom_override_user", "Override Username set via custom selector");
      assert(trickyPass.value === "OverridePassword123!", "Override Password set via custom selector");
      responseCalled = true;
    });
    assert(responseCalled, "Custom override callback executed");
    console.log("✓ Test 7: Per-Domain Custom Field Override - PASSED");
  }

  // Test 8: Page Field Inspection Listener
  {
    const field1 = createMockInput({ id: "login_user", type: "text", name: "user" });
    const field2 = createMockInput({ id: "login_pass", type: "password", name: "pass" });
    global.document.children = [field1, field2];

    let responseCalled = false;
    chromeListeners[0]({ action: "inspect_page_fields" }, {}, (res) => {
      assert(res.success === true, "Inspection action succeeded");
      assert(res.fields.length === 2, "2 fields detected");
      assert(res.fields[0].selector === "#login_user", "Field 1 selector generated");
      assert(res.fields[1].selector === "#login_pass", "Field 2 selector generated");
      responseCalled = true;
    });
    assert(responseCalled, "Inspection callback executed");
    console.log("✓ Test 8: Local Page Field Inspection Listener - PASSED");
  }

  console.log("All content script tests PASSED successfully!");
}

try {
  runTests();
} catch (e) {
  console.error("FAIL:", e.message);
  process.exit(1);
}
