const hasNativeBridge = Boolean(window.webkit?.messageHandlers?.generalsX);
const nativePending = new Map();
let nativeRequestCounter = 0;
let nativeState = null;
let nativeDiagnosticsText = "";

window.GeneralsXNative = {
  request(action, payload = {}, timeoutMs = 20000) {
    if (!hasNativeBridge) return Promise.reject(new Error("Native bridge is unavailable"));
    const id = `gx-${Date.now()}-${++nativeRequestCounter}`;
    return new Promise((resolve, reject) => {
      const timer = window.setTimeout(() => {
        nativePending.delete(id);
        reject(new Error(`Native action timed out: ${action}`));
      }, timeoutMs);
      nativePending.set(id, {
        resolve(value) { window.clearTimeout(timer); resolve(value); },
        reject(error) { window.clearTimeout(timer); reject(error); }
      });
      try {
        window.webkit.messageHandlers.generalsX.postMessage({ id, action, payload });
      } catch (error) {
        window.clearTimeout(timer);
        nativePending.delete(id);
        reject(error);
      }
    });
  },

  _receive(envelope) {
    if (!envelope || typeof envelope !== "object") return;

    if (envelope.type === "response") {
      const pending = nativePending.get(envelope.id);
      if (!pending) return;
      nativePending.delete(envelope.id);
      if (envelope.ok) pending.resolve(envelope.result);
      else pending.reject(new Error(envelope.error || "Native request failed"));
      return;
    }

    if (envelope.type === "event") {
      handleNativeEvent(envelope.name, envelope.payload || {});
    }
  }
};

function nativeRequest(action, payload = {}) {
  return window.GeneralsXNative.request(action, payload);
}

function nativeProfileIdForCard(card = activeCard) {
  const id = card?.dataset?.id || "zero-hour-online";
  if (id === "zero-hour-online") return "online";
  return id;
}

function nativeModState(modId) {
  return nativeState?.mods?.find(item => item.profileId === modId) || null;
}

function nativeProfileState(profileId) {
  if (profileId === "online") return nativeState?.online || null;
  return nativeModState(profileId);
}

function applyNativeState(state) {
  if (!state || typeof state !== "object") return;
  nativeState = state;

  installedMods = (state.mods || [])
    .filter(item => item.installed)
    .map(item => item.profileId);

  (state.mods || []).forEach(item => {
    const mod = modCatalog.find(candidate => candidate.id === item.profileId);
    if (!mod) return;
    mod.title = item.name || mod.title;
    mod.description = item.description || mod.description;
    mod.version = item.version || "";
    mod.installedVersion = item.installedVersion || "";
    mod.updateAvailable = Boolean(item.updateAvailable);
    mod.packageBytes = Number(item.packageBytes || 0);
    mod.releaseNotes = item.releaseNotes || "";
    if (item.sourceURL) mod.moddbUrl = item.sourceURL;
    if (item.author) mod.author = item.author;
  });

  syncInstalledModCards();
  syncActiveModSourceLink();
  syncNativeSystemStatus();

  if (!modalBackdrop.hidden && modalTitle.textContent === "Add Mod") {
    renderModLibrary();
  }
}

function syncNativeSystemStatus() {
  if (!nativeState) return;
  const engine = document.querySelector("#systemEngine");
  const launcher = document.querySelector("#systemLauncher");
  const gameData = document.querySelector("#systemGameData");
  const profiles = document.querySelector("#systemProfiles");
  const footerBuild = document.querySelector("#footerBuild");

  if (engine) engine.textContent = nativeState.engineVersion || "unknown";
  if (launcher) launcher.textContent =
    `${nativeState.launcherVersion || "unknown"} · web ${nativeState.launcherWebVersion || "bundled"}`;
  const onlineInstalled = Boolean(nativeState.online?.installed);
  if (gameData) {
    gameData.textContent = onlineInstalled ? "Ready" : "Not installed";
    gameData.classList.toggle("good", onlineInstalled);
  }
  if (profiles) {
    const installedCount = (onlineInstalled ? 1 : 0) + (nativeState.mods || []).filter(item => item.installed).length;
    profiles.textContent = `${installedCount} ready`;
  }
  if (footerBuild) footerBuild.textContent = `BUILD ${nativeState.build || "unknown"}`;

  const currentProfileId = nativeProfileIdForCard();
  const profile = nativeProfileState(currentProfileId);
  const installed = Boolean(profile?.installed);
  const updateAvailable = Boolean(profile?.updateAvailable);
  statusLabel.textContent = installed ? (updateAvailable ? "UPDATE" : "READY") : "NOT INSTALLED";
  statusLabel.classList.toggle("status-text--warning", !installed || updateAvailable);
  statusLabel.classList.toggle("status-text--ready", installed && !updateAvailable);
  playLabel.textContent = !installed ? "INSTALL" : (updateAvailable ? "UPDATE" : "PLAY");
}

async function syncNativeState() {
  if (!hasNativeBridge) return;
  try {
    applyNativeState(await nativeRequest("getState"));
  } catch (error) {
    showToast(error.message || "Unable to read launcher state");
  }
}

function updateNativeProgress(payload) {
  const modId = payload.profileId;
  const progress = document.querySelector(`[data-mod-progress="${modId}"]`);
  const bar = progress?.querySelector("span");
  const fraction = Math.max(0, Math.min(1, Number(payload.fraction || 0)));
  if (progress) progress.style.display = "block";
  if (bar) bar.style.width = `${Math.round(fraction * 100)}%`;

  const mod = modCatalog.find(item => item.id === modId);
  const title = mod?.title || (modId === "online" ? "Zero Hour + Online" : modId);
  const received = Number(payload.received || 0) / 1024 / 1024 / 1024;
  const total = Number(payload.total || 0) / 1024 / 1024 / 1024;
  showToast(total > 0
    ? `${title}: ${Math.round(fraction * 100)}% · ${received.toFixed(2)} / ${total.toFixed(2)} GB`
    : `${title}: downloading…`);
}

function handleNativeEvent(name, payload) {
  if (name === "stateChanged") {
    applyNativeState(payload);
    return;
  }
  if (name === "downloadProgress") {
    updateNativeProgress(payload);
    return;
  }
  if (name === "installComplete") {
    const title = modCatalog.find(item => item.id === payload.profileId)?.title ||
      (payload.profileId === "online" ? "Zero Hour + Online" : payload.profileId);
    showToast(`${title} installed`);
    syncNativeState();
    return;
  }
  if (name === "installError") {
    showToast(payload.error || "Install failed");
    syncNativeState();
  }
}

const cards = [...document.querySelectorAll(".mode-card")];
const hero = document.querySelector(".hero");
const modeTitle = document.querySelector("#modeTitle");
const modeDescription = document.querySelector("#modeDescription");
const profileLabel = document.querySelector("#profileLabel");
const statusLabel = document.querySelector("#statusLabel");
const playLabel = document.querySelector("#playLabel");
const playButton = document.querySelector("#playButton");
const detailsButton = document.querySelector("#detailsButton");
const toast = document.querySelector("#toast");
const modalBackdrop = document.querySelector("#modalBackdrop");
const modalClose = document.querySelector("#modalClose");
const modalTitle = document.querySelector("#modalTitle");
const modalEyebrow = document.querySelector("#modalEyebrow");
const modalBody = document.querySelector("#modalBody");
const modSourceLink = document.querySelector("#modSourceLink");
const modesRail = document.querySelector(".modes");
const addModCard = document.querySelector(".add-mod-card");
const audioToggle = document.querySelector("#audioToggle");

const backgroundPrimary = document.querySelector(".battlefield__tile--primary");
const backgroundSecondary = document.querySelector(".battlefield__tile--secondary");
const backgroundGrid = document.querySelector(".battlefield__grid");

const backgroundSlides = [
  "./assets/bg1.png",
  "./assets/bg2.png",
  "./assets/bg3.png",
  "./assets/bg4.png"
];

const backgroundLayers = [backgroundPrimary, backgroundSecondary];
let activeBackgroundLayer = 0;
let activeBackgroundIndex = -1;
let backgroundSlideTimer = null;
let backgroundFadeFrame = null;

let activeCard = cards[0];
let toastTimer;
let modalCloseTimer = null;
let uiAudioContext = null;
let uiSoundEnabled = (() => {
  try { return localStorage.getItem("generals-x-ui-sound") !== "off"; }
  catch { return true; }
})();

const uiSoundProfiles = {
  tap: [[310, 250, 0.045, 0.020]],
  select: [[390, 520, 0.070, 0.026], [690, 760, 0.045, 0.012]],
  open: [[260, 390, 0.085, 0.020], [520, 650, 0.070, 0.010]],
  close: [[410, 275, 0.075, 0.018]],
  play: [[180, 230, 0.095, 0.032], [520, 690, 0.090, 0.016]],
  confirm: [[470, 660, 0.080, 0.024]]
};

function ensureUIAudio() {
  if (!uiSoundEnabled) return null;
  if (!uiAudioContext) {
    const AudioContextClass = window.AudioContext || window.webkitAudioContext;
    if (!AudioContextClass) return null;
    uiAudioContext = new AudioContextClass();
  }
  if (uiAudioContext.state === "suspended") uiAudioContext.resume().catch(() => {});
  return uiAudioContext;
}

function playUISound(name = "tap") {
  if (!uiSoundEnabled) return;
  const context = ensureUIAudio();
  if (!context) return;
  const profile = uiSoundProfiles[name] || uiSoundProfiles.tap;
  const now = context.currentTime;
  profile.forEach(([from, to, duration, volume], index) => {
    const oscillator = context.createOscillator();
    const gain = context.createGain();
    oscillator.type = index === 0 ? "triangle" : "sine";
    oscillator.frequency.setValueAtTime(from, now);
    oscillator.frequency.exponentialRampToValueAtTime(Math.max(40, to), now + duration);
    gain.gain.setValueAtTime(0.0001, now);
    gain.gain.exponentialRampToValueAtTime(volume, now + 0.008);
    gain.gain.exponentialRampToValueAtTime(0.0001, now + duration);
    oscillator.connect(gain);
    gain.connect(context.destination);
    oscillator.start(now);
    oscillator.stop(now + duration + 0.01);
  });
}

function syncAudioToggle() {
  if (!audioToggle) return;
  audioToggle.classList.toggle("is-muted", !uiSoundEnabled);
  audioToggle.setAttribute("aria-pressed", String(!uiSoundEnabled));
  audioToggle.setAttribute("aria-label", uiSoundEnabled ? "Mute interface sounds" : "Enable interface sounds");
  audioToggle.title = uiSoundEnabled ? "Mute interface sounds" : "Enable interface sounds";
}

function animateInteraction(target) {
  if (!target) return;
  target.classList.remove("is-pressed");
  void target.offsetWidth;
  target.classList.add("is-pressed");
  window.setTimeout(() => target.classList.remove("is-pressed"), 180);
}

const modCatalog = [
  {
    id: "enhanced",
    title: "Enhanced",
    description: "Modernized Zero Hour profile with its own visual, UI and AI options.",
    author: "Acoustic Alpha",
    moddbUrl: "https://www.moddb.com/mods/cc-generals-zero-hour-enhanced"
  },
  {
    id: "contra-x",
    title: "Contra X",
    description: "Contra X Beta 2 + Patch 1 with dedicated mod settings.",
    author: "Contra Mod Team",
    moddbUrl: "https://www.moddb.com/mods/contra"
  }
];

function loadInstalledMods() {
  try {
    const saved = JSON.parse(localStorage.getItem("generals-x-launcher-demo-installed-mods") || "[]");
    return Array.isArray(saved) ? saved.filter(id => modCatalog.some(mod => mod.id === id)) : [];
  } catch {
    return [];
  }
}

let installedMods = loadInstalledMods();

function saveInstalledMods() {
  try {
    localStorage.setItem("generals-x-launcher-demo-installed-mods", JSON.stringify(installedMods));
  } catch {
    // Demo still works without persistent browser storage.
  }
}

function isModInstalled(modId) {
  return installedMods.includes(modId);
}

function updateModesOverflow() {
  if (!modesRail) return;
  window.requestAnimationFrame(() => {
    const overflowing = modesRail.scrollWidth > modesRail.clientWidth + 2;
    modesRail.classList.toggle("is-overflowing", overflowing);
  });
}

function syncModeCardVersions() {
  const baseCard = cards.find(item => item.dataset.id === "zero-hour-online");
  const baseVersion = nativeState?.online?.installedVersion || nativeState?.online?.version || "1.04";
  const baseSmall = baseCard?.querySelector("small");
  if (baseSmall) baseSmall.textContent = `${baseVersion} · Multiplayer`;

  modCatalog.forEach(mod => {
    const card = cards.find(item => item.dataset.id === mod.id);
    const small = card?.querySelector("small");
    if (!small) return;
    small.textContent = mod.installedVersion || mod.version || (mod.id === "contra-x" ? "Beta 2 · Patch 1" : "Installed");
  });
}

function syncInstalledModCards() {
  const hasInstalledMods = installedMods.length > 0;
  const baseCard = cards.find(item => item.dataset.id === "zero-hour-online");
  if (baseCard) baseCard.hidden = !hasInstalledMods;

  modCatalog.forEach(mod => {
    const card = cards.find(item => item.dataset.id === mod.id);
    if (card) card.hidden = !isModInstalled(mod.id);
  });

  syncModeCardVersions();
  updateModesOverflow();
}

function syncActiveModSourceLink() {
  if (!modSourceLink) return;

  const mod = modCatalog.find(item => item.id === activeCard?.dataset.id);
  const shouldShow = Boolean(mod && isModInstalled(mod.id));

  modSourceLink.hidden = !shouldShow;

  if (!shouldShow) {
    modSourceLink.removeAttribute("href");
    modSourceLink.removeAttribute("title");
    return;
  }

  modSourceLink.href = mod.moddbUrl;
  modSourceLink.title = `Original mod on ModDB — ${mod.author}`;
}

const settingsDefaults = {
  game: {
    shadow3D: false,
    shadow2D: true,
    cloudShadows: false,
    groundLighting: true,
    softWater: true,
    buildingOcclusion: true,
    showProps: true,
    extraAnimations: true,
    dynamicLOD: false,
    heatEffects: false,
    textureQuality: "High",
    particles: "Medium",
    textureFilter: "Anisotropic",
    anisotropy: "8x",
    msaa: "Off",
    maxCamera: 550,
    minCamera: 70,
    cameraPitch: 37,
    enforceMax: false,
    scrollSpeed: 1.0,
    drawDistance: 1.20,
    fpsLimit: true,
    fps: 60
  },
  enhanced: {
    textureResolution: "High",
    uiQuality: "FHD",
    infantryIconScale: "100%",
    cameos: "HD",
    aiScripts: "Default"
  },
  contra: {
    controlBar: "Contra",
    cameos: "Standard",
    music: "Standard",
    voices: "English",
    hotkeys: "Original",
    hotkeyLanguage: "English",
    portraits: "Standard",
    fogEffects: false,
    waterEffects: true,
    extraBuildingProps: true
  }
};

function cloneSettingsDefaults() {
  return JSON.parse(JSON.stringify(settingsDefaults));
}

function loadDemoSettings() {
  try {
    const saved = localStorage.getItem("generals-x-launcher-demo-settings");
    if (!saved) return cloneSettingsDefaults();
    const parsed = JSON.parse(saved);
    return {
      game: { ...settingsDefaults.game, ...(parsed.game || {}) },
      enhanced: { ...settingsDefaults.enhanced, ...(parsed.enhanced || {}) },
      contra: { ...settingsDefaults.contra, ...(parsed.contra || {}) }
    };
  } catch {
    return cloneSettingsDefaults();
  }
}

let settingsState = loadDemoSettings();

function showToast(message) {
  window.clearTimeout(toastTimer);
  toast.textContent = message;
  toast.classList.add("is-visible");
  toastTimer = window.setTimeout(() => {
    toast.classList.remove("is-visible");
  }, 2200);
}

function setActiveCard(card) {
  if (!card || card === activeCard) return;

  cards.forEach(item => item.classList.toggle("is-active", item === card));
  activeCard = card;

  hero.classList.add("is-switching");

  window.setTimeout(() => {
    modeTitle.textContent = card.dataset.title;
    modeTitle.classList.toggle("is-long-title", card.dataset.id === "zero-hour-online");
    modeDescription.textContent = card.dataset.description;
    profileLabel.textContent = card.dataset.profile;
    statusLabel.textContent = card.dataset.status;
    playLabel.textContent = "PLAY";

    const experimental = card.dataset.status === "EXPERIMENTAL";
    statusLabel.classList.toggle("status-text--warning", experimental);
    statusLabel.classList.toggle("status-text--ready", !experimental);

    syncActiveModSourceLink();
    if (hasNativeBridge) syncNativeSystemStatus();

    hero.classList.remove("is-switching");
    card.scrollIntoView({ behavior: "smooth", block: "nearest", inline: "nearest" });
  }, 155);
}

cards.forEach(card => {
  card.addEventListener("click", () => setActiveCard(card));
});

playButton.addEventListener("click", async () => {
  const profileId = nativeProfileIdForCard();
  if (!hasNativeBridge) {
    showToast("Demo: launch request for " + activeCard.dataset.title);
    return;
  }

  const profile = nativeProfileState(profileId);
  const installed = Boolean(profile?.installed);
  const updateAvailable = Boolean(profile?.updateAvailable);

  if (!installed || updateAvailable) {
    try {
      if (profile?.packageURL) {
        await nativeRequest("install", { profileId });
        showToast(`${updateAvailable ? "Updating" : "Downloading"} ${activeCard.dataset.title}…`);
      } else {
        await nativeRequest("chooseFile", { profileId });
        showToast(`Choose the ${activeCard.dataset.title} package`);
      }
    } catch (error) {
      showToast(error.message || "Install failed");
    }
    return;
  }

  if (profileId !== "online" && !nativeState?.online?.installed) {
    showToast("Install Zero Hour + Online base content first");
    return;
  }

  try {
    await nativeRequest("play", { profileId });
    showToast(`Starting ${activeCard.dataset.title}…`);
  } catch (error) {
    showToast(error.message || "Launch failed");
  }
});

detailsButton.addEventListener("click", () => {
  openPanel("details");
});

function openPanel(type) {
  if (type === "settings" && hasNativeBridge) {
    const profileId = nativeProfileIdForCard();
    nativeRequest("settings", { profileId }).catch(error => showToast(error.message || "Settings failed"));
    return;
  }

  window.clearTimeout(modalCloseTimer);
  modalBackdrop.hidden = false;
  window.requestAnimationFrame(() => modalBackdrop.classList.add("is-visible"));

  if (type === "settings") {
    const profileId = nativeProfileIdForCard();

    modalEyebrow.textContent = activeCard.dataset.profile;
    modalTitle.textContent =
      profileId === "enhanced"
        ? "Enhanced settings"
        : profileId === "contra-x"
          ? "Contra X settings"
          : "Zero Hour + Online settings";
    renderSettings(profileId);
  } else if (type === "mods") {
    modalEyebrow.textContent = "GENERALS X";
    modalTitle.textContent = "Add Mod";
    renderModLibrary();
  } else if (type === "diagnostics") {
    modalEyebrow.textContent = "SYSTEM";
    modalTitle.textContent = "Diagnostics";
    renderDiagnostics();
  } else {
    modalEyebrow.textContent = activeCard.dataset.profile;
    modalTitle.textContent = activeCard.dataset.title;
    modalBody.innerHTML = `
      <div class="setting-section">
        <h3>Profile information</h3>
        <div class="setting-row"><span>Status</span><strong>${activeCard.dataset.status}</strong></div>
        <div class="setting-row"><span>Target</span><strong>iPad / Mac</strong></div>
        <div class="setting-row"><span>Launcher mode</span><strong>Web UI · native bridge</strong></div>
      </div>
      <div class="setting-section">
        <h3>Description</h3>
        <p style="margin:0;color:rgba(255,255,255,.68);font-size:13px;line-height:1.7">${activeCard.dataset.description}</p>
      </div>
    `;
  }
}


function humanSize(bytes) {
  const value = Number(bytes || 0);
  if (!value) return "";
  if (value >= 1024 ** 3) return `${(value / 1024 ** 3).toFixed(1)} GB`;
  if (value >= 1024 ** 2) return `${(value / 1024 ** 2).toFixed(0)} MB`;
  return `${Math.round(value / 1024)} KB`;
}

function modInstallActions(mod) {
  const nativeMod = nativeModState(mod.id);
  const installed = isModInstalled(mod.id);
  const busy = Boolean(nativeState?.download?.busy);
  const activeDownload = nativeState?.download?.profileId === mod.id;
  const updateAvailable = Boolean(nativeMod?.updateAvailable || mod.updateAvailable);

  const progress = `
    <div class="mod-download-progress" data-mod-progress="${mod.id}" style="${activeDownload ? "display:block" : "display:none"}"><span></span></div>
  `;

  if (installed) {
    return `
      <div class="mod-installed">
        <svg class="lucide lucide-circle-check" viewBox="0 0 24 24" aria-hidden="true">
          <circle cx="12" cy="12" r="10"/>
          <path d="m9 12 2 2 4-4"/>
        </svg>
        ${updateAvailable ? `Installed ${mod.installedVersion || ""} · update ${mod.version || ""}` : `Installed ${mod.installedVersion || mod.version || ""}`}
      </div>
      ${updateAvailable ? `
        <button type="button" class="mod-install-button mod-install-button--primary" data-mod-download="${mod.id}" ${busy ? "disabled" : ""}>
          Update
        </button>` : ""}
      <button type="button" class="mod-install-button" data-mod-remove="${mod.id}" ${busy ? "disabled" : ""}>Remove</button>
      ${progress}
    `;
  }

  return `
    <button type="button" class="mod-install-button mod-install-button--primary" data-mod-download="${mod.id}" ${busy ? "disabled" : ""}>
      <svg class="lucide lucide-cloud-download" viewBox="0 0 24 24" aria-hidden="true">
        <path d="M12 13v8M8 17l4 4 4-4"/>
        <path d="M20.39 18.39A5 5 0 0 0 18 9h-1.26A8 8 0 1 0 3 16.3"/>
      </svg>
      ${activeDownload ? "Downloading…" : "Download"}
    </button>
    <button type="button" class="mod-install-button" data-mod-file="${mod.id}" ${busy ? "disabled" : ""}>
      <svg class="lucide lucide-file-up" viewBox="0 0 24 24" aria-hidden="true">
        <path d="M14.5 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V7.5L14.5 2z"/>
        <polyline points="14 2 14 8 20 8"/>
        <path d="M12 18v-6M9 15l3-3 3 3"/>
      </svg>
      Choose File
    </button>
    <input class="mod-file-input" type="file" data-mod-file-input="${mod.id}">
    ${progress}
  `;
}

function renderModLibrary() {
  modalBody.innerHTML = `
    <div class="mod-library">
      <div class="mod-library__toolbar">
        <div class="segment-control mod-channel-control">
          <button type="button" data-channel="stable" class="${(nativeState?.channel || "stable") === "stable" ? "is-selected" : ""}">Stable</button>
          <button type="button" data-channel="beta" class="${nativeState?.channel === "beta" ? "is-selected" : ""}">Beta</button>
        </div>
        <button type="button" class="diagnostics-action" data-catalog-refresh>Refresh</button>
      </div>
      <p class="mod-library__intro">Install or update profiles from the Generals X catalog. Only one large package is downloaded at a time.</p>
      ${modCatalog.map(mod => `
        <div class="mod-library-card" data-mod-card="${mod.id}">
          <div class="mod-library-card__copy">
            <strong>${mod.title}</strong>
            <span>${mod.description}</span>
            <span class="mod-version-line">${mod.version ? `Version ${mod.version}` : ""}${mod.packageBytes ? ` · ${humanSize(mod.packageBytes)}` : ""}</span>
            <a class="mod-author-link" href="${mod.moddbUrl}" target="_blank" rel="noopener noreferrer">
              <svg class="lucide lucide-external-link" viewBox="0 0 24 24" aria-hidden="true">
                <path d="M15 3h6v6"/>
                <path d="M10 14 21 3"/>
                <path d="M18 13v6a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2h6"/>
              </svg>
              Original mod by ${mod.author} · ModDB
            </a>
          </div>
          <div class="mod-library-card__actions">
            ${modInstallActions(mod)}
          </div>
        </div>
      `).join("")}
    </div>
  `;

  modalBody.querySelectorAll("[data-mod-download]").forEach(button => {
    button.addEventListener("click", () => {
      if (hasNativeBridge) installNativeMod(button.dataset.modDownload, button);
      else simulateCloudInstall(button.dataset.modDownload, button);
    });
  });

  modalBody.querySelectorAll("[data-mod-remove]").forEach(button => {
    button.addEventListener("click", async () => {
      try {
        const state = await nativeRequest("remove", { profileId: button.dataset.modRemove });
        applyNativeState(state);
        showToast("Mod removed");
      } catch (error) {
        showToast(error.message || "Remove failed");
      }
    });
  });

  modalBody.querySelectorAll("[data-channel]").forEach(button => {
    button.addEventListener("click", async () => {
      if (!hasNativeBridge) return;
      try {
        applyNativeState(await nativeRequest("setChannel", { channel: button.dataset.channel }));
        showToast(`${button.dataset.channel.toUpperCase()} channel active`);
      } catch (error) {
        showToast(error.message || "Channel switch failed");
      }
    });
  });

  modalBody.querySelector("[data-catalog-refresh]")?.addEventListener("click", async () => {
    if (!hasNativeBridge) return;
    try {
      applyNativeState(await nativeRequest("refreshCatalog"));
      showToast("Catalog refreshed");
    } catch (error) {
      showToast(error.message || "Refresh failed");
    }
  });

  modalBody.querySelectorAll("[data-mod-file]").forEach(button => {
    button.addEventListener("click", () => {
      if (hasNativeBridge) {
        nativeRequest("chooseFile", { profileId: button.dataset.modFile })
          .catch(error => showToast(error.message || "File picker failed"));
        return;
      }
      const input = modalBody.querySelector(`[data-mod-file-input="${button.dataset.modFile}"]`);
      input?.click();
    });
  });

  modalBody.querySelectorAll("[data-mod-file-input]").forEach(input => {
    input.addEventListener("change", () => {
      if (!input.files || input.files.length === 0) return;
      installMod(input.dataset.modFileInput, "file");
    });
  });
}


async function installNativeMod(modId, button) {
  const mod = modCatalog.find(item => item.id === modId);
  if (!mod) return;

  button.disabled = true;
  try {
    await nativeRequest("install", { profileId: modId });
    showToast(`Downloading ${mod.title}…`);
  } catch (error) {
    button.disabled = false;
    showToast(error.message || "Download failed");
  }
}

function simulateCloudInstall(modId, button) {
  const card = button.closest("[data-mod-card]");
  const progress = card?.querySelector(`[data-mod-progress="${modId}"]`);
  const bar = progress?.querySelector("span");
  const buttons = card?.querySelectorAll(".mod-install-button") || [];

  buttons.forEach(item => item.disabled = true);
  if (progress) progress.style.display = "block";

  let value = 0;
  const timer = window.setInterval(() => {
    value = Math.min(100, value + 12);
    if (bar) bar.style.width = `${value}%`;

    if (value >= 100) {
      window.clearInterval(timer);
      window.setTimeout(() => installMod(modId, "cloud"), 180);
    }
  }, 95);
}

function installMod(modId, source) {
  const mod = modCatalog.find(item => item.id === modId);
  if (!mod) return;

  if (!isModInstalled(modId)) {
    installedMods.push(modId);
    saveInstalledMods();
  }

  syncInstalledModCards();

  const card = cards.find(item => item.dataset.id === modId);
  if (card) setActiveCard(card);

  showToast(`${mod.title} installed${source === "file" ? " from file" : ""}`);
  window.setTimeout(closePanel, 220);
}

function diagnosticsReport() {
  return `APP
Project: Generals X
Bundle: demo
Platform: Local browser
Device: ${navigator.platform || "Unknown"}

BUILD
Launcher: demo-01
Launcher run: local
Engine: 0.1.0
Base shell run: local

CONTENT
GameData: Installed
Zero Hour + Online: Installed
Enhanced: ${isModInstalled("enhanced") ? "Installed" : "Not installed"}
Contra X: ${isModInstalled("contra") ? "Installed" : "Not installed"}

FILES
iPad settings: Present
Enhanced settings: ${isModInstalled("enhanced") ? "Present" : "n/a"}
Contra settings: ${isModInstalled("contra") ? "Present" : "n/a"}
Current session: Yes
Session logs: 1/10`;
}

function renderDiagnostics() {
  modalBody.innerHTML = `
    <p class="diagnostics-note">Build, installed content and crash logs. A copy is saved automatically to Files > On My iPad > Generals ZH > Diagnostics.</p>
    <div class="diagnostic-block" id="diagnosticReport">${diagnosticsReport()}</div>
    <div class="diagnostics-actions">
      <button type="button" class="diagnostics-action" data-diagnostics-refresh>Refresh</button>
      <button type="button" class="diagnostics-action" data-diagnostics-export>Save to Files</button>
      <button type="button" class="diagnostics-action" data-diagnostics-share>Share report + logs</button>
      <button type="button" class="diagnostics-action diagnostics-action--danger" data-diagnostics-clear>Clear logs</button>
    </div>
  `;

  const refreshDiagnostics = async () => {
    if (!hasNativeBridge) {
      modalBody.querySelector("#diagnosticReport").textContent = diagnosticsReport();
      showToast("Diagnostics refreshed");
      return;
    }
    try {
      const result = await nativeRequest("diagnostics");
      nativeDiagnosticsText = result?.report || "";
      modalBody.querySelector("#diagnosticReport").textContent = nativeDiagnosticsText || "No diagnostics available.";
      if (result?.exportPath) showToast(`Diagnostics saved: ${result.exportPath}`);
    } catch (error) {
      modalBody.querySelector("#diagnosticReport").textContent = error.message || "Diagnostics failed";
    }
  };

  modalBody.querySelector("[data-diagnostics-refresh]").addEventListener("click", refreshDiagnostics);
  if (hasNativeBridge) refreshDiagnostics();

  modalBody.querySelector("[data-diagnostics-export]").addEventListener("click", async () => {
    if (!hasNativeBridge) {
      showToast("Native bridge is unavailable");
      return;
    }
    showToast("Saving diagnostics to Files…");
    try {
      const result = await nativeRequest("exportDiagnostics");
      showToast(`Saved ${result?.fileCount || 0} files · ${result?.path || "Diagnostics"}`);
    } catch (error) {
      showToast(error.message || "Save failed");
    }
  });

  modalBody.querySelector("[data-diagnostics-share]").addEventListener("click", async () => {
    if (hasNativeBridge) {
      showToast("Opening share sheet…");
      try {
        await nativeRequest("shareDiagnostics");
      } catch (error) {
        showToast(error.message || "Share failed");
      }
      return;
    }
    const report = diagnosticsReport();
    try {
      if (navigator.share) {
        await navigator.share({ title: "Generals X diagnostics", text: report });
      } else if (navigator.clipboard) {
        await navigator.clipboard.writeText(report);
        showToast("Report copied");
      } else {
        showToast("Share is unavailable in this browser");
      }
    } catch {
      // User cancellation is not an error for this demo.
    }
  });

  modalBody.querySelector("[data-diagnostics-clear]").addEventListener("click", async () => {
    if (hasNativeBridge) {
      try {
        await nativeRequest("clearDiagnostics");
        showToast("Clear dialog opened");
      } catch (error) {
        showToast(error.message || "Clear failed");
      }
    } else {
      showToast("Demo logs cleared");
    }
  });
}

function segmentControl(scope, key, choices) {
  const value = settingsState[scope][key];
  return `
    <div class="segment-control" data-scope="${scope}" data-key="${key}">
      ${choices.map(choice => `
        <button type="button" class="${choice === value ? "is-selected" : ""}" data-value="${choice}">${choice}</button>
      `).join("")}
    </div>
  `;
}

function toggleControl(scope, key) {
  const enabled = Boolean(settingsState[scope][key]);
  return `
    <button type="button" class="switch-control ${enabled ? "is-on" : ""}" data-scope="${scope}" data-key="${key}" aria-pressed="${enabled}">
      <span></span>
    </button>
  `;
}

function rangeControl(scope, key, min, max, step, suffix = "") {
  const value = settingsState[scope][key];
  return `
    <div class="range-control">
      <input type="range" min="${min}" max="${max}" step="${step}" value="${value}" data-scope="${scope}" data-key="${key}">
      <output>${value}${suffix}</output>
    </div>
  `;
}

function settingRow(label, control) {
  return `<div class="setting-row"><span>${label}</span><div class="setting-control">${control}</div></div>`;
}

function renderGameSettings() {
  return `
    <div class="setting-section">
      <h3>Graphics</h3>
      ${settingRow("3D shadows", toggleControl("game", "shadow3D"))}
      ${settingRow("2D shadows", toggleControl("game", "shadow2D"))}
      ${settingRow("Cloud shadows", toggleControl("game", "cloudShadows"))}
      ${settingRow("Ground lighting", toggleControl("game", "groundLighting"))}
      ${settingRow("Smooth water borders", toggleControl("game", "softWater"))}
      ${settingRow("Units behind buildings", toggleControl("game", "buildingOcclusion"))}
      ${settingRow("Small props / trees", toggleControl("game", "showProps"))}
      ${settingRow("Extra animations", toggleControl("game", "extraAnimations"))}
      ${settingRow("Dynamic LOD", toggleControl("game", "dynamicLOD"))}
      ${settingRow("Heat effects", toggleControl("game", "heatEffects"))}
      ${settingRow("Texture quality", segmentControl("game", "textureQuality", ["High", "Medium", "Low"]))}
      ${settingRow("Particles", segmentControl("game", "particles", ["Low", "Medium", "High"]))}
      ${settingRow("Texture filtering", segmentControl("game", "textureFilter", ["Bilinear", "Trilinear", "Anisotropic"]))}
      ${settingRow("Anisotropy", segmentControl("game", "anisotropy", ["2x", "4x", "8x", "16x"]))}
      ${settingRow("MSAA", segmentControl("game", "msaa", ["Off", "2x", "4x", "8x"]))}
    </div>

    <div class="setting-section">
      <h3>Camera / Performance</h3>
      ${settingRow("Maximum camera height", rangeControl("game", "maxCamera", 300, 800, 10))}
      ${settingRow("Minimum camera height", rangeControl("game", "minCamera", 40, 150, 5))}
      ${settingRow("Camera pitch", rangeControl("game", "cameraPitch", 20, 60, 1, "°"))}
      ${settingRow("Enforce maximum camera height", toggleControl("game", "enforceMax"))}
      ${settingRow("Keyboard / edge scroll speed", rangeControl("game", "scrollSpeed", 0.5, 2, 0.1, "×"))}
      ${settingRow("Terrain draw distance", rangeControl("game", "drawDistance", 0.5, 2, 0.05, "×"))}
      ${settingRow("FPS limit", toggleControl("game", "fpsLimit"))}
      ${settingRow("Frames per second", rangeControl("game", "fps", 30, 120, 5, " FPS"))}
    </div>
  `;
}

function renderEnhancedSettings() {
  return `
    <div class="setting-section">
      <h3>Enhanced</h3>
      ${settingRow("Faction textures", segmentControl("enhanced", "textureResolution", ["Vanilla", "High"]))}
      ${settingRow("UI quality", segmentControl("enhanced", "uiQuality", ["HD", "FHD", "QHD"]))}
      ${settingRow("Infantry icons", segmentControl("enhanced", "infantryIconScale", ["100%", "75%", "50%"]))}
      ${settingRow("Cameos", segmentControl("enhanced", "cameos", ["SD", "HD"]))}
      ${settingRow("AI scripts", segmentControl("enhanced", "aiScripts", ["Default", "Restrained", "Skynet"]))}
    </div>
  `;
}

function renderContraSettings() {
  return `
    <div class="setting-section">
      <h3>Contra X</h3>
      ${settingRow("Control Bar", segmentControl("contra", "controlBar", ["Contra", "Pro", "Standard"]))}
      ${settingRow("Icon / cameo quality", segmentControl("contra", "cameos", ["Standard", "HD"]))}
      ${settingRow("Music", segmentControl("contra", "music", ["Standard", "Enhanced", "The Score"]))}
      ${settingRow("Unit voices", segmentControl("contra", "voices", ["English", "Native"]))}
      ${settingRow("Hotkeys", segmentControl("contra", "hotkeys", ["Original", "Leikeze"]))}
      ${settingRow("Hotkey language", segmentControl("contra", "hotkeyLanguage", ["English", "Russian"]))}
      ${settingRow("General portraits", segmentControl("contra", "portraits", ["Standard", "Funny"]))}
      ${settingRow("Fog effects", toggleControl("contra", "fogEffects"))}
      ${settingRow("Water effects", toggleControl("contra", "waterEffects"))}
      ${settingRow("Extra building props", toggleControl("contra", "extraBuildingProps"))}
    </div>
  `;
}

function renderSettings(profileId = "zero-hour-online") {
  const scope =
    profileId === "enhanced"
      ? "enhanced"
      : profileId === "contra-x"
        ? "contra"
        : "game";

  const content =
    scope === "enhanced"
      ? renderEnhancedSettings()
      : scope === "contra"
        ? renderContraSettings()
        : renderGameSettings();

  modalBody.innerHTML = `
    <div class="settings-content">
      ${content}
    </div>

    <div class="settings-actions">
      <button type="button" class="settings-action settings-action--primary" data-settings-save>Save</button>
      <button type="button" class="settings-action" data-settings-reset>Reset defaults</button>
    </div>
  `;

  modalBody.querySelectorAll(".segment-control button").forEach(button => {
    button.addEventListener("click", () => {
      const parent = button.closest(".segment-control");
      settingsState[parent.dataset.scope][parent.dataset.key] = button.dataset.value;
      parent.querySelectorAll("button").forEach(item => item.classList.toggle("is-selected", item === button));
    });
  });

  modalBody.querySelectorAll(".switch-control").forEach(button => {
    button.addEventListener("click", () => {
      const scope = button.dataset.scope;
      const key = button.dataset.key;
      settingsState[scope][key] = !settingsState[scope][key];
      button.classList.toggle("is-on", settingsState[scope][key]);
      button.setAttribute("aria-pressed", String(settingsState[scope][key]));
    });
  });

  modalBody.querySelectorAll(".range-control input").forEach(input => {
    input.addEventListener("input", () => {
      const scope = input.dataset.scope;
      const key = input.dataset.key;
      const value = Number(input.value);
      settingsState[scope][key] = value;
      const suffix = key === "cameraPitch" ? "°" : key === "fps" ? " FPS" : ["scrollSpeed", "drawDistance"].includes(key) ? "×" : "";
      input.parentElement.querySelector("output").textContent = value + suffix;
    });
  });

  modalBody.querySelector("[data-settings-save]").addEventListener("click", () => {
    try {
      localStorage.setItem("generals-x-launcher-demo-settings", JSON.stringify(settingsState));
    } catch {
      // The visual demo still works if browser storage is unavailable.
    }
    showToast(`${activeCard.dataset.title} settings saved`);
  });

  modalBody.querySelector("[data-settings-reset]").addEventListener("click", () => {
    settingsState[scope] = { ...settingsDefaults[scope] };
    renderSettings(profileId);
    showToast("Default settings loaded");
  });
}

function preloadBackgroundSlides() {
  return Promise.all(
    backgroundSlides.map(src => new Promise(resolve => {
      const image = new Image();
      image.onload = () => resolve(src);
      image.onerror = () => resolve(src);
      image.src = src;
    }))
  );
}

function randomBackgroundIndex(excludeIndex = -1) {
  const choices = backgroundSlides
    .map((_, index) => index)
    .filter(index => index !== excludeIndex);

  return choices[Math.floor(Math.random() * choices.length)];
}

function scheduleNextBackgroundSlide() {
  window.clearTimeout(backgroundSlideTimer);
  const delay = 10000 + Math.random() * 5000;
  backgroundSlideTimer = window.setTimeout(showNextBackgroundSlide, delay);
}

function showNextBackgroundSlide() {
  if (!backgroundPrimary || !backgroundSecondary) return;

  const nextIndex = randomBackgroundIndex(activeBackgroundIndex);
  const nextLayerIndex = activeBackgroundLayer === 0 ? 1 : 0;
  const currentLayer = backgroundLayers[activeBackgroundLayer];
  const nextLayer = backgroundLayers[nextLayerIndex];

  if (backgroundFadeFrame !== null) {
    cancelAnimationFrame(backgroundFadeFrame);
    backgroundFadeFrame = null;
  }

  nextLayer.style.backgroundImage = 'url("' + backgroundSlides[nextIndex] + '")';
  nextLayer.style.opacity = "0";
  currentLayer.style.opacity = "1";

  const fadeDuration = 7600;
  const fadeStart = performance.now();

  function fadeFrame(now) {
    const progress = Math.min(1, (now - fadeStart) / fadeDuration);
    const eased = progress * progress * progress * (progress * (progress * 6 - 15) + 10);

    nextLayer.style.opacity = String(eased);
    currentLayer.style.opacity = String(1 - eased);

    if (progress < 1) {
      backgroundFadeFrame = requestAnimationFrame(fadeFrame);
      return;
    }

    nextLayer.style.opacity = "1";
    currentLayer.style.opacity = "0";
    backgroundFadeFrame = null;
    activeBackgroundLayer = nextLayerIndex;
    activeBackgroundIndex = nextIndex;
    scheduleNextBackgroundSlide();
  }

  backgroundFadeFrame = requestAnimationFrame(fadeFrame);
}

function startBackgroundMotion() {
  if (!backgroundPrimary || !backgroundSecondary) return;

  activeBackgroundIndex = randomBackgroundIndex();
  backgroundPrimary.style.backgroundImage = 'url("' + backgroundSlides[activeBackgroundIndex] + '")';
  backgroundPrimary.style.opacity = "1";
  backgroundSecondary.style.opacity = "0";

  preloadBackgroundSlides().then(() => {
    scheduleNextBackgroundSlide();
  });

  let parallaxX = 0;
  let parallaxY = 0;
  let targetX = 0;
  let targetY = 0;

  window.addEventListener("pointermove", event => {
    targetX = -(event.clientX / window.innerWidth - 0.5) * 8;
    targetY = -(event.clientY / window.innerHeight - 0.5) * 5;
  }, { passive: true });

  window.addEventListener("pointerleave", () => {
    targetX = 0;
    targetY = 0;
  });

  const start = performance.now();

  function frame(now) {
    const elapsed = now - start;
    parallaxX += (targetX - parallaxX) * 0.014;
    parallaxY += (targetY - parallaxY) * 0.014;

    const driftX = elapsed * 0.0088;
    const driftY = elapsed * 0.0034;
    const waveX = Math.sin(elapsed / 7600) * 9;
    const waveY = Math.cos(elapsed / 9200) * 5;

    const primaryX = driftX + waveX + parallaxX;
    const primaryY = driftY + waveY + parallaxY;
    const secondaryX = driftX + waveX * 0.82 + parallaxX * 0.8 + 34;
    const secondaryY = driftY + waveY * 0.82 + parallaxY * 0.8 + 18;

    backgroundPrimary.style.backgroundPosition =
      primaryX + "px " + primaryY + "px";

    backgroundSecondary.style.backgroundPosition =
      secondaryX + "px " + secondaryY + "px";

    if (backgroundGrid) {
      backgroundGrid.style.transform =
        "translate3d(" + (-parallaxX * 0.14) + "px, " + (-parallaxY * 0.14) + "px, 0)";
    }

    requestAnimationFrame(frame);
  }

  requestAnimationFrame(frame);
}

document.querySelectorAll("[data-panel]").forEach(button => {
  button.addEventListener("click", () => openPanel(button.dataset.panel));
});

if (audioToggle) {
  syncAudioToggle();
  audioToggle.addEventListener("click", () => {
    uiSoundEnabled = !uiSoundEnabled;
    try { localStorage.setItem("generals-x-ui-sound", uiSoundEnabled ? "on" : "off"); } catch {}
    syncAudioToggle();
    if (uiSoundEnabled) playUISound("confirm");
    showToast(uiSoundEnabled ? "Interface sounds on" : "Interface sounds off");
  });
}

document.addEventListener("pointerdown", event => {
  const target = event.target.closest("button, a");
  if (!target || target.disabled) return;
  animateInteraction(target);
  const sound = target === playButton
    ? "play"
    : target.classList.contains("mode-card")
      ? "select"
      : target === modalClose
        ? "close"
        : target.matches("[data-panel]")
          ? "open"
          : "tap";
  playUISound(sound);
}, { passive: true });

if (modesRail) {
  modesRail.addEventListener("wheel", event => {
    if (!modesRail.classList.contains("is-overflowing")) return;
    if (Math.abs(event.deltaY) <= Math.abs(event.deltaX)) return;
    event.preventDefault();
    modesRail.scrollBy({ left: event.deltaY, behavior: "smooth" });
  }, { passive: false });

  if (window.ResizeObserver) {
    const railObserver = new ResizeObserver(updateModesOverflow);
    railObserver.observe(modesRail);
  } else {
    window.addEventListener("resize", updateModesOverflow, { passive: true });
  }
}

function closePanel() {
  if (modalBackdrop.hidden) return;
  modalBackdrop.classList.remove("is-visible");
  window.clearTimeout(modalCloseTimer);
  modalCloseTimer = window.setTimeout(() => {
    modalBackdrop.hidden = true;
  }, 220);
}

modalClose.addEventListener("click", closePanel);
modalBackdrop.addEventListener("click", event => {
  if (event.target === modalBackdrop) closePanel();
});

window.addEventListener("keydown", event => {
  if (event.key === "Escape") closePanel();

  if (["ArrowLeft", "ArrowRight"].includes(event.key)) {
    const visibleCards = cards.filter(card => !card.hidden);
    const currentIndex = visibleCards.indexOf(activeCard);
    const delta = event.key === "ArrowRight" ? 1 : -1;
    const next = visibleCards[(currentIndex + delta + visibleCards.length) % visibleCards.length];
    if (next) {
      setActiveCard(next);
      next.focus();
    }
  }
});

syncInstalledModCards();
syncActiveModSourceLink();
updateModesOverflow();

startBackgroundMotion();

if (hasNativeBridge) {
  syncNativeState();
}