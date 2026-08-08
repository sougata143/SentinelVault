document.addEventListener("DOMContentLoaded", async () => {
  const statusBadge = document.getElementById("status-badge");
  const lockedView = document.getElementById("locked-view");
  const unlockedView = document.getElementById("unlocked-view");
  const credentialList = document.getElementById("credential-list");

  const toggleMappingBtn = document.getElementById("toggle-mapping-btn");
  const mappingContainer = document.getElementById("mapping-container");
  const mappingArrow = document.getElementById("mapping-arrow");
  const usernameSelectorInput = document.getElementById("username-selector-input");
  const passwordSelectorInput = document.getElementById("password-selector-input");
  const saveMappingBtn = document.getElementById("save-mapping-btn");
  const clearMappingBtn = document.getElementById("clear-mapping-btn");

  const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
  if (!tab || !tab.url) {
    statusBadge.textContent = "Locked";
    statusBadge.className = "status-badge status-locked";
    lockedView.style.display = "block";
    return;
  }

  let origin = "";
  let hostname = "";
  try {
    const url = new URL(tab.url);
    if (!url.protocol.startsWith("http")) {
      statusBadge.textContent = "Locked";
      statusBadge.className = "status-badge status-locked";
      lockedView.style.display = "block";
      return;
    }
    origin = url.origin;
    hostname = url.hostname;
  } catch (_) {
    statusBadge.textContent = "Locked";
    statusBadge.className = "status-badge status-locked";
    lockedView.style.display = "block";
    return;
  }

  // Handle Collapsible Mapping Drawer
  toggleMappingBtn.addEventListener("click", () => {
    const isHidden = mappingContainer.style.display === "none";
    mappingContainer.style.display = isHidden ? "block" : "none";
    mappingArrow.textContent = isHidden ? "▲" : "▼";
  });

  // Load existing domain override from local storage if available
  let activeDomainOverride = null;
  if (chrome.storage && chrome.storage.local) {
    chrome.storage.local.get(["sentinel_domain_overrides"], (result) => {
      const overrides = result.sentinel_domain_overrides || {};
      activeDomainOverride = overrides[hostname] || null;

      if (activeDomainOverride) {
        usernameSelectorInput.value = activeDomainOverride.usernameSelector || "";
        passwordSelectorInput.value = activeDomainOverride.passwordSelector || "";
        clearMappingBtn.style.display = "block";
      }
    });
  }

  // Save Domain Override
  saveMappingBtn.addEventListener("click", () => {
    const userSel = usernameSelectorInput.value.trim();
    const passSel = passwordSelectorInput.value.trim();

    if (!userSel && !passSel) return;

    if (chrome.storage && chrome.storage.local) {
      chrome.storage.local.get(["sentinel_domain_overrides"], (result) => {
        const overrides = result.sentinel_domain_overrides || {};
        overrides[hostname] = {
          usernameSelector: userSel,
          passwordSelector: passSel
        };
        chrome.storage.local.set({ sentinel_domain_overrides: overrides }, () => {
          activeDomainOverride = overrides[hostname];
          clearMappingBtn.style.display = "block";
          saveMappingBtn.textContent = "Saved!";
          setTimeout(() => {
            saveMappingBtn.textContent = "Save Domain Override";
          }, 1500);
        });
      });
    }
  });

  // Clear Domain Override
  clearMappingBtn.addEventListener("click", () => {
    if (chrome.storage && chrome.storage.local) {
      chrome.storage.local.get(["sentinel_domain_overrides"], (result) => {
        const overrides = result.sentinel_domain_overrides || {};
        delete overrides[hostname];
        chrome.storage.local.set({ sentinel_domain_overrides: overrides }, () => {
          activeDomainOverride = null;
          usernameSelectorInput.value = "";
          passwordSelectorInput.value = "";
          clearMappingBtn.style.display = "none";
        });
      });
    }
  });

  chrome.runtime.sendMessage({ action: "get_status" }, (statusResponse) => {
    if (!statusResponse || !statusResponse.unlocked || statusResponse.locked) {
      statusBadge.textContent = "Locked";
      statusBadge.className = "status-badge status-locked";
      lockedView.style.display = "block";
      unlockedView.style.display = "none";
    } else {
      statusBadge.textContent = "Unlocked";
      statusBadge.className = "status-badge status-unlocked";
      lockedView.style.display = "none";
      unlockedView.style.display = "block";

      chrome.runtime.sendMessage({ action: "get_credentials", origin: origin }, (credResponse) => {
        credentialList.innerHTML = "";
        if (credResponse && credResponse.items && credResponse.items.length > 0) {
          credResponse.items.forEach((item) => {
            const li = document.createElement("li");
            li.className = "credential-item";

            const infoDiv = document.createElement("div");
            infoDiv.className = "cred-info";

            const titleSpan = document.createElement("span");
            titleSpan.className = "cred-title";
            titleSpan.textContent = item.title;

            const userSpan = document.createElement("span");
            userSpan.className = "cred-user";
            userSpan.textContent = item.username;

            infoDiv.appendChild(titleSpan);
            infoDiv.appendChild(userSpan);

            const btn = document.createElement("button");
            btn.className = "btn-autofill";
            btn.textContent = "Autofill";
            btn.addEventListener("click", () => {
              chrome.tabs.sendMessage(tab.id, {
                action: "autofill_credentials",
                origin: origin,
                credentials: {
                  username: item.username,
                  password: item.password
                },
                domainOverride: activeDomainOverride
              }, (autofillRes) => {
                if (autofillRes && autofillRes.success) {
                  window.close();
                }
              });
            });

            li.appendChild(infoDiv);
            li.appendChild(btn);
            credentialList.appendChild(li);
          });
        } else {
          const li = document.createElement("li");
          li.className = "no-items";
          li.textContent = "No matching items for this website.";
          credentialList.appendChild(li);
        }
      });
    }
  });
});
