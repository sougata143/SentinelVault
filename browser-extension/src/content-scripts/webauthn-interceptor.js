// WebAuthn API Interceptor Content Script for SentinelVault Browser Extension

(function () {
  'use strict';

  // Security Check: Do not inject into cross-origin iframes
  if (window.top !== window.self) {
    return;
  }

  // Inject WebAuthn Polyfill script into the page context
  const scriptContent = `
    (function() {
      if (!window.navigator || !window.navigator.credentials) return;

      const originalCreate = window.navigator.credentials.create.bind(window.navigator.credentials);
      const originalGet = window.navigator.credentials.get.bind(window.navigator.credentials);

      function bufferToBase64Url(buffer) {
        if (!buffer) return '';
        const bytes = new Uint8Array(buffer);
        let binary = '';
        for (let i = 0; i < bytes.byteLength; i++) {
          binary += String.fromCharCode(bytes[i]);
        }
        return btoa(binary).replace(/\\+/g, '-').replace(/\\//g, '_').replace(/=/g, '');
      }

      function base64UrlToBuffer(base64url) {
        if (!base64url) return new ArrayBuffer(0);
        let base64 = base64url.replace(/-/g, '+').replace(/_/g, '/');
        while (base64.length % 4) {
          base64 += '=';
        }
        const binary = atob(base64);
        const bytes = new Uint8Array(binary.length);
        for (let i = 0; i < binary.length; i++) {
          bytes[i] = binary.charCodeAt(i);
        }
        return bytes.buffer;
      }

      window.navigator.credentials.create = async function(options) {
        if (!options || !options.publicKey) {
          return originalCreate(options);
        }

        const pk = options.publicKey;
        const payload = {
          action: "WEBAUTHN_REGISTER",
          origin: window.location.origin,
          rpId: pk.rp ? pk.rp.id : window.location.hostname,
          rpName: pk.rp ? pk.rp.name : '',
          userName: pk.user ? pk.user.name : '',
          userHandle: pk.user ? bufferToBase64Url(pk.user.id) : '',
          challenge: bufferToBase64Url(pk.challenge)
        };

        return new Promise((resolve, reject) => {
          const requestId = "webauthn_reg_" + Math.random().toString(36).substring(2);
          
          function handleResponse(event) {
            if (event.source !== window || !event.data || event.data.requestId !== requestId || event.data.type === "SENTINEL_WEBAUTHN_REQUEST") return;
            window.removeEventListener('message', handleResponse);

            if (event.data.success) {
              const res = event.data.credential;
              const attestation = {
                id: res.id,
                rawId: base64UrlToBuffer(res.id),
                type: 'public-key',
                response: {
                  clientDataJSON: base64UrlToBuffer(res.clientDataJSON),
                  attestationObject: base64UrlToBuffer(res.attestationObject)
                },
                getClientExtensionResults: () => ({})
              };
              resolve(attestation);
            } else {
              reject(new DOMException(event.data.error || "Passkey registration cancelled", "NotAllowedError"));
            }
          }

          window.addEventListener('message', handleResponse);
          window.postMessage({ type: "SENTINEL_WEBAUTHN_REQUEST", requestId: requestId, payload: payload }, "*");
        });
      };

      window.navigator.credentials.get = async function(options) {
        if (!options || !options.publicKey) {
          return originalGet(options);
        }

        const pk = options.publicKey;
        const payload = {
          action: "WEBAUTHN_ASSERT",
          origin: window.location.origin,
          rpId: pk.rpId || window.location.hostname,
          challenge: bufferToBase64Url(pk.challenge)
        };

        return new Promise((resolve, reject) => {
          const requestId = "webauthn_get_" + Math.random().toString(36).substring(2);

          function handleResponse(event) {
            if (event.source !== window || !event.data || event.data.requestId !== requestId || event.data.type === "SENTINEL_WEBAUTHN_REQUEST") return;
            window.removeEventListener('message', handleResponse);

            if (event.data.success) {
              const res = event.data.assertion;
              const assertion = {
                id: res.id,
                rawId: base64UrlToBuffer(res.id),
                type: 'public-key',
                response: {
                  authenticatorData: base64UrlToBuffer(res.authenticatorData),
                  clientDataJSON: base64UrlToBuffer(res.clientDataJSON),
                  signature: base64UrlToBuffer(res.signature),
                  userHandle: res.userHandle ? base64UrlToBuffer(res.userHandle) : null
                },
                getClientExtensionResults: () => ({})
              };
              resolve(assertion);
            } else {
              reject(new DOMException(event.data.error || "Passkey authentication cancelled", "NotAllowedError"));
            }
          }

          window.addEventListener('message', handleResponse);
          window.postMessage({ type: "SENTINEL_WEBAUTHN_REQUEST", requestId: requestId, payload: payload }, "*");
        });
      };
    })();
  `;

  // Inject page polyfill script element into document head
  const scriptEl = document.createElement('script');
  scriptEl.textContent = scriptContent;
  (document.head || document.documentElement).appendChild(scriptEl);
  scriptEl.remove();

  // Listen to messages from injected page script and relay to extension background script
  window.addEventListener('message', (event) => {
    if (event.source !== window || !event.data || event.data.type !== "SENTINEL_WEBAUTHN_REQUEST") return;

    const { requestId, payload } = event.data;

    chrome.runtime.sendMessage(payload, (response) => {
      const err = chrome.runtime.lastError;
      if (err) {
        window.postMessage({ requestId: requestId, success: false, error: err.message }, "*");
      } else if (response && response.success) {
        window.postMessage({ requestId: requestId, success: true, credential: response.credential, assertion: response.assertion }, "*");
      } else {
        window.postMessage({ requestId: requestId, success: false, error: (response && response.error) || "Passkey operation failed" }, "*");
      }
    });
  });

})();
