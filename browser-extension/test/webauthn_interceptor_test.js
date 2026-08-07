const fs = require('fs');
const path = require('path');

// 1. Setup Mock Environment
global.window = {
  top: {},
  self: {},
  location: {
    origin: "https://github.com",
    hostname: "github.com"
  },
  navigator: {
    credentials: {
      create: async () => ({ mock: "original_create" }),
      get: async () => ({ mock: "original_get" })
    }
  },
  listeners: {},
  addEventListener: (event, cb) => {
    global.window.listeners[event] = global.window.listeners[event] || [];
    global.window.listeners[event].push(cb);
  },
  removeEventListener: (event, cb) => {
    if (global.window.listeners[event]) {
      global.window.listeners[event] = global.window.listeners[event].filter(fn => fn !== cb);
    }
  },
  postMessage: (msg, targetOrigin) => {
    // Dispatch to registered message listeners asynchronously
    setTimeout(() => {
      if (global.window.listeners['message']) {
        global.window.listeners['message'].forEach(cb => cb({ source: global.window, data: msg }));
      }
    }, 5);
  }
};

global.window.top = global.window;
global.window.self = global.window;

global.document = {
  head: {
    appendChild: (el) => {
      if (el && el.textContent) {
        eval(el.textContent);
      }
    }
  },
  documentElement: {
    appendChild: (el) => {
      if (el && el.textContent) {
        eval(el.textContent);
      }
    }
  },
  createElement: (tag) => ({
    remove: () => {}
  })
};

global.btoa = (str) => Buffer.from(str, 'binary').toString('base64');
global.atob = (b64) => Buffer.from(b64, 'base64').toString('binary');
global.DOMException = class DOMException extends Error {
  constructor(message, name) {
    super(message);
    this.name = name;
  }
};

// Mock chrome runtime messaging API
const chromeListeners = [];
const chromeSentMessages = [];

global.chrome = {
  runtime: {
    onMessage: {
      addListener: (cb) => {
        chromeListeners.push(cb);
      }
    },
    sendMessage: (msg, cb) => {
      chromeSentMessages.push(msg);
      // Simulate background worker response
      if (msg.action === "WEBAUTHN_REGISTER") {
        cb({
          success: true,
          credential: {
            id: "mock_cred_id_123",
            clientDataJSON: "eyJ0eXBlIjoid2ViYXV0aG4uY3JlYXRlIn0",
            attestationObject: "o2NmbXRobm9uZWRhdHRTdG10o2FhdXRoRGF0YV..."
          }
        });
      } else if (msg.action === "WEBAUTHN_ASSERT") {
        cb({
          success: true,
          assertion: {
            id: "mock_cred_id_123",
            authenticatorData: "SZYN5YgOjGh0NBcPZHZgW4_kCr8...",
            clientDataJSON: "eyJ0eXBlIjoid2ViYXV0aG4uZ2V0In0",
            signature: "MEUCIQD...",
            userHandle: "user_handle_abc"
          }
        });
      } else {
        cb({ success: false, error: "Unknown action" });
      }
    }
  }
};

// Load content script code
const scriptPath = path.join(__dirname, '../src/content-scripts/webauthn-interceptor.js');
const code = fs.readFileSync(scriptPath, 'utf8');
eval(code);

function assert(condition, message) {
  if (!condition) {
    throw new Error("Assertion Failed: " + message);
  }
}

async function runTests() {
  console.log("Running WebAuthn Interceptor Content Script Tests...");

  // Test 1: Intercept navigator.credentials.create()
  {
    chromeSentMessages.length = 0;
    const options = {
      publicKey: {
        rp: { id: "github.com", name: "GitHub" },
        user: { id: new Uint8Array([1, 2, 3, 4]).buffer, name: "dev@sentinelvault.io" },
        challenge: new Uint8Array([10, 20, 30, 40]).buffer,
        pubKeyCredParams: [{ alg: -7, type: "public-key" }]
      }
    };

    const credential = await window.navigator.credentials.create(options);
    assert(credential !== null, "Credential object returned");
    assert(credential.type === "public-key", "Type is public-key");
    assert(credential.id === "mock_cred_id_123", "Credential ID matches");
    assert(chromeSentMessages.length === 1, "Background message sent");
    assert(chromeSentMessages[0].action === "WEBAUTHN_REGISTER", "Action is WEBAUTHN_REGISTER");
    assert(chromeSentMessages[0].rpId === "github.com", "rpId matches");
    assert(chromeSentMessages[0].userName === "dev@sentinelvault.io", "userName matches");
    console.log("✓ Test 1: WebAuthn Passkey Registration (create) - PASSED");
  }

  // Test 2: Intercept navigator.credentials.get()
  {
    chromeSentMessages.length = 0;
    const options = {
      publicKey: {
        rpId: "github.com",
        challenge: new Uint8Array([50, 60, 70, 80]).buffer
      }
    };

    const assertion = await window.navigator.credentials.get(options);
    assert(assertion !== null, "Assertion object returned");
    assert(assertion.type === "public-key", "Type is public-key");
    assert(assertion.id === "mock_cred_id_123", "Assertion credential ID matches");
    assert(assertion.response.authenticatorData instanceof ArrayBuffer, "authenticatorData is ArrayBuffer");
    assert(assertion.response.signature instanceof ArrayBuffer, "signature is ArrayBuffer");
    assert(chromeSentMessages.length === 1, "Background message sent");
    assert(chromeSentMessages[0].action === "WEBAUTHN_ASSERT", "Action is WEBAUTHN_ASSERT");
    assert(chromeSentMessages[0].rpId === "github.com", "rpId matches");
    console.log("✓ Test 2: WebAuthn Passkey Assertion (get) - PASSED");
  }

  console.log("All WebAuthn Interceptor tests PASSED successfully!");
}

runTests().catch(e => {
  console.error("FAIL:", e);
  process.exit(1);
});
