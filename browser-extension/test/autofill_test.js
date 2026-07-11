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

global.document = {
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
  querySelectorAll: () => []
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

  // Test 3: Credential capture triggers on form submit
  {
    sentMessages.length = 0; // Clear history
    global.location.origin = "https://example.com";

    // Create a mock form submit event
    const mockForm = {
      querySelector: (selector) => {
        if (selector.includes('input[type="password"]')) {
          return { value: "my-secret-password" };
        }
        if (selector.includes('input[type="text"]')) {
          return { value: "my-username" };
        }
        return null;
      }
    };

    // Trigger submit listener
    const submitHandlers = global.document.listeners['submit'];
    assert(submitHandlers && submitHandlers.length > 0, "Submit listener must be registered");
    submitHandlers.forEach(handler => handler({ target: mockForm }));

    assert(sentMessages.length === 1, "Should send captured credential message");
    assert(sentMessages[0].action === "captured_credential", "Action should be captured_credential");
    assert(sentMessages[0].username === "my-username", "Username matches");
    assert(sentMessages[0].password === "my-secret-password", "Password matches");
    assert(sentMessages[0].origin === "https://example.com", "Origin matches");
    console.log("✓ Test 3: Credential capture on submit - PASSED");
  }

  console.log("All content script tests PASSED successfully!");
}

try {
  runTests();
} catch (e) {
  console.error("FAIL:", e.message);
  process.exit(1);
}
