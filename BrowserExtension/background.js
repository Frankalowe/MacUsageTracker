// Mac Usage Tracker Companion Extension
// Communicates with local Mac Usage Tracker app on http://127.0.0.1:48123

function reportActiveTab() {
  chrome.tabs.query({ active: true, lastFocusedWindow: true }, (tabs) => {
    if (!tabs || !tabs[0] || !tabs[0].url) return;
    try {
      const url = new URL(tabs[0].url);
      if (url.protocol === "http:" || url.protocol === "https:") {
        const domain = url.hostname.replace(/^www\./, "");
        if (domain) {
          fetch(`http://127.0.0.1:48123/domain?name=${encodeURIComponent(domain)}`, { method: "GET" })
            .catch(() => {
              // App may not be running currently
            });
        }
      }
    } catch (e) {
      // Ignore internal urls (e.g. chrome://, brave://, about:)
    }
  });
}

// 1. Listen for active tab switch
chrome.tabs.onActivated.addListener(reportActiveTab);

// 2. Listen for navigation / page completion
chrome.tabs.onUpdated.addListener((tabId, changeInfo) => {
  if (changeInfo.url || changeInfo.status === "complete") {
    reportActiveTab();
  }
});

// 3. Listen for window focus changes
chrome.windows.onFocusChanged.addListener((windowId) => {
  if (windowId !== chrome.windows.WINDOW_ID_NONE) {
    reportActiveTab();
  }
});

// 4. Heartbeat report every 3 seconds while browser is in focus
setInterval(reportActiveTab, 3000);
