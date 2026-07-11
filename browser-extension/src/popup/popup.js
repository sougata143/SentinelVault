document.addEventListener("DOMContentLoaded", async () => {
  const statusBadge = document.getElementById("status-badge");
  const lockedView = document.getElementById("locked-view");
  const unlockedView = document.getElementById("unlocked-view");
  const credentialList = document.getElementById("credential-list");

  const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
  if (!tab || !tab.url) {
    statusBadge.textContent = "Locked";
    statusBadge.className = "status-badge status-locked";
    lockedView.style.display = "block";
    return;
  }

  // Handle browser settings pages or invalid protocols gracefully
  let origin = "";
  try {
    const url = new URL(tab.url);
    if (!url.protocol.startsWith("http")) {
      statusBadge.textContent = "Locked";
      statusBadge.className = "status-badge status-locked";
      lockedView.style.display = "block";
      return;
    }
    origin = url.origin;
  } catch (_) {
    statusBadge.textContent = "Locked";
    statusBadge.className = "status-badge status-locked";
    lockedView.style.display = "block";
    return;
  }

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
                }
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
