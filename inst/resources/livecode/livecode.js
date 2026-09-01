"use strict";

let revision = null;
let pollingInterval = 750;
let socket = null;
let pollTimer = null;
let reconnectTimer = null;
let connectionTimer = null;
let polling = false;
let reconnectDelay = 2000;
let sourceText = "";

const source = document.getElementById("source");
const status = document.getElementById("status");
const copySource = document.getElementById("copy-source");

async function copyText(text) {
  if (navigator.clipboard && window.isSecureContext) {
    await navigator.clipboard.writeText(text);
    return;
  }

  const textarea = document.createElement("textarea");
  textarea.value = text;
  textarea.setAttribute("readonly", "");
  textarea.style.position = "fixed";
  textarea.style.opacity = "0";
  document.body.appendChild(textarea);
  textarea.select();

  const copied = document.execCommand("copy");
  textarea.remove();
  if (!copied) {
    throw new Error("Copy command was rejected");
  }
}

copySource.addEventListener("click", async function() {
  try {
    await copyText(sourceText);
    copySource.textContent = "Copied";
    copySource.dataset.state = "copied";
  } catch (error) {
    copySource.textContent = "Try again";
    copySource.dataset.state = "error";
  }

  window.setTimeout(() => {
    copySource.textContent = "Copy";
    delete copySource.dataset.state;
  }, 1500);
});

function renderState(state) {
  if (typeof state.interval === "number") {
    pollingInterval = state.interval * 1000;
  }

  if (state.error) {
    status.textContent = state.error;
    status.dataset.state = "error";
  } else {
    status.textContent = socket && socket.readyState === WebSocket.OPEN
      ? "Live · WebSocket"
      : "Live · HTTP fallback";
    status.dataset.state = "live";
  }

  if (state.changed && typeof state.content === "string") {
    sourceText = state.content;
    source.textContent = sourceText;
    copySource.disabled = false;
    revision = state.revision;
    if (window.Prism) {
      Prism.highlightElement(source);
    }
  }
}

async function poll() {
  if (!polling) {
    return;
  }

  const query = revision === null ? "" : `?revision=${revision}`;

  try {
    const response = await fetch(`/__livecode__/poll${query}`, {
      cache: "no-store"
    });
    if (!response.ok) {
      throw new Error(`HTTP ${response.status}`);
    }

    const state = await response.json();
    renderState(state);
  } catch (error) {
    status.textContent = `Disconnected: ${error.message}`;
    status.dataset.state = "error";
  } finally {
    if (polling) {
      pollTimer = window.setTimeout(poll, pollingInterval);
    }
  }
}

function startPolling() {
  if (polling) {
    return;
  }
  polling = true;
  poll();
}

function stopPolling() {
  polling = false;
  window.clearTimeout(pollTimer);
  pollTimer = null;
}

function scheduleReconnect() {
  window.clearTimeout(reconnectTimer);
  const jitter = Math.random() * 1000;
  reconnectTimer = window.setTimeout(connectWebSocket, reconnectDelay + jitter);
  reconnectDelay = Math.min(reconnectDelay * 2, 30000);
}

function connectWebSocket() {
  const protocol = window.location.protocol === "https:" ? "wss:" : "ws:";
  try {
    socket = new WebSocket(`${protocol}//${window.location.host}/__livecode__/ws`);
  } catch (error) {
    startPolling();
    scheduleReconnect();
    return;
  }

  connectionTimer = window.setTimeout(() => {
    if (socket.readyState !== WebSocket.OPEN) {
      startPolling();
      socket.close();
    }
  }, 2000);

  socket.onopen = function() {
    window.clearTimeout(connectionTimer);
    reconnectDelay = 2000;
    stopPolling();
    status.textContent = "Live · WebSocket";
    status.dataset.state = "live";
  };

  socket.onmessage = function(message) {
    renderState(JSON.parse(message.data));
  };

  socket.onerror = function() {
    startPolling();
  };

  socket.onclose = function() {
    window.clearTimeout(connectionTimer);
    startPolling();
    scheduleReconnect();
  };
}

connectWebSocket();
