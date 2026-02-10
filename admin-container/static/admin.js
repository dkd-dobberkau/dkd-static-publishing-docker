// ============================================================
// Static Publishing Admin – Client
// ============================================================

const $ = (s) => document.querySelector(s);

// Elements
const dropzone = $("#dropzone");
const fileInput = $("#fileInput");
const deployForm = $("#deployForm");
const deployProgress = $("#deployProgress");
const deployResult = $("#deployResult");
const appsList = $("#appsList");

let selectedFile = null;
let deleteTarget = null;

// ----------------------------------------------------------
// Drag & Drop + File Selection
// ----------------------------------------------------------

dropzone.addEventListener("click", () => fileInput.click());

dropzone.addEventListener("dragover", (e) => {
  e.preventDefault();
  dropzone.classList.add("drag-over");
});

dropzone.addEventListener("dragleave", () => {
  dropzone.classList.remove("drag-over");
});

dropzone.addEventListener("drop", (e) => {
  e.preventDefault();
  dropzone.classList.remove("drag-over");
  const file = e.dataTransfer.files[0];
  if (file) handleFileSelect(file);
});

fileInput.addEventListener("change", (e) => {
  if (e.target.files[0]) handleFileSelect(e.target.files[0]);
});

function handleFileSelect(file) {
  if (!file.name.endsWith(".zip")) {
    alert("Bitte eine .zip-Datei auswählen");
    return;
  }
  selectedFile = file;
  $("#fileName").textContent = file.name;
  $("#fileSize").textContent = humanSize(file.size);

  // Suggest app name from filename
  const suggested = file.name
    .replace(/\.zip$/i, "")
    .replace(/[^a-z0-9-]/gi, "-")
    .replace(/-+/g, "-")
    .replace(/^-|-$/g, "")
    .toLowerCase();
  $("#appName").value = suggested;

  dropzone.style.display = "none";
  deployForm.style.display = "block";
  deployResult.style.display = "none";
  deployProgress.style.display = "none";
}

$("#clearFile").addEventListener("click", resetDeploy);

function resetDeploy() {
  selectedFile = null;
  fileInput.value = "";
  dropzone.style.display = "block";
  deployForm.style.display = "none";
  deployProgress.style.display = "none";
  deployResult.style.display = "none";
}

$("#resetBtn").addEventListener("click", resetDeploy);

// ----------------------------------------------------------
// Deploy
// ----------------------------------------------------------

$("#deployBtn").addEventListener("click", async () => {
  const appName = $("#appName").value.trim();
  if (!appName) {
    $("#appName").focus();
    return;
  }
  if (!/^[a-z0-9][a-z0-9-]*[a-z0-9]$|^[a-z0-9]$/.test(appName)) {
    alert("App-Name: nur Kleinbuchstaben, Zahlen und Bindestriche. Darf nicht mit Bindestrich anfangen oder enden.");
    return;
  }
  if (!selectedFile) return;

  const clean = $("#cleanDeploy").checked;
  const formData = new FormData();
  formData.append("file", selectedFile);
  formData.append("clean", clean);

  // Show progress
  deployForm.style.display = "none";
  deployProgress.style.display = "block";
  $("#progressFill").style.width = "0%";
  $("#progressText").textContent = "Wird hochgeladen...";

  try {
    // Use XMLHttpRequest for progress tracking
    const result = await uploadWithProgress(
      `/api/apps/${encodeURIComponent(appName)}/deploy`,
      formData,
      (pct) => {
        $("#progressFill").style.width = pct + "%";
        if (pct < 100) {
          $("#progressText").textContent = `Hochladen... ${pct}%`;
        } else {
          $("#progressText").textContent = "Server verarbeitet...";
        }
      }
    );

    // Show success
    deployProgress.style.display = "none";
    deployResult.style.display = "block";
    $("#resultIcon").textContent = "✓";
    $("#resultIcon").classList.remove("error");
    $("#resultText").textContent = `${result.uploaded} Dateien deployed`;
    $("#resultLink").textContent = result.url;
    $("#resultLink").href = result.url;

    // Refresh list
    loadApps();
  } catch (err) {
    deployProgress.style.display = "none";
    deployResult.style.display = "block";
    $("#resultIcon").textContent = "✕";
    $("#resultIcon").classList.add("error");
    $("#resultText").textContent = err.message || "Deployment fehlgeschlagen";
    $("#resultLink").textContent = "";
    $("#resultLink").href = "#";
  }
});

function uploadWithProgress(url, formData, onProgress) {
  return new Promise((resolve, reject) => {
    const xhr = new XMLHttpRequest();
    xhr.open("POST", url);

    xhr.upload.addEventListener("progress", (e) => {
      if (e.lengthComputable) {
        onProgress(Math.round((e.loaded / e.total) * 100));
      }
    });

    xhr.addEventListener("load", () => {
      try {
        const data = JSON.parse(xhr.responseText);
        if (xhr.status >= 200 && xhr.status < 300) {
          resolve(data);
        } else {
          reject(new Error(data.detail || data.error || `HTTP ${xhr.status}`));
        }
      } catch {
        reject(new Error(`HTTP ${xhr.status}`));
      }
    });

    xhr.addEventListener("error", () => reject(new Error("Netzwerkfehler")));
    xhr.send(formData);
  });
}

// ----------------------------------------------------------
// App List
// ----------------------------------------------------------

async function loadApps() {
  appsList.innerHTML = '<div class="apps-loading">Lade Apps...</div>';

  try {
    const res = await fetch("/api/apps");
    const data = await res.json();

    if (!data.apps || data.apps.length === 0) {
      appsList.innerHTML = '<div class="apps-empty">Noch keine Apps deployed</div>';
      return;
    }

    appsList.innerHTML = data.apps
      .map(
        (app) => {
          const name = escapeHtml(app.name);
          const url = escapeHtml(app.url);
          const meta = escapeHtml(app.last_modified_human);
          const size = escapeHtml(app.total_size_human);
          return `
      <div class="app-row">
        <div class="app-info">
          <div class="app-name"><a href="${url}" target="_blank" rel="noopener">/${name}/</a></div>
          <div class="app-meta">${meta}</div>
        </div>
        <span class="app-stat">${app.file_count} Dateien</span>
        <span class="app-stat">${size}</span>
        <div style="display:flex;gap:4px">
          <button class="btn-icon" onclick="invalidateApp('${name}', this)" title="Cache invalidieren">↻</button>
          <button class="btn-icon danger" onclick="confirmDelete('${name}')" title="Löschen">✕</button>
        </div>
      </div>`;
        }
      )
      .join("");
  } catch (err) {
    appsList.innerHTML = `<div class="apps-empty">Fehler beim Laden: ${err.message}</div>`;
  }
}

$("#refreshBtn").addEventListener("click", loadApps);

// ----------------------------------------------------------
// Delete
// ----------------------------------------------------------

window.confirmDelete = function (appName) {
  deleteTarget = appName;
  $("#deleteAppName").textContent = appName;
  $("#deleteModal").style.display = "flex";
};

$("#cancelDelete").addEventListener("click", () => {
  $("#deleteModal").style.display = "none";
  deleteTarget = null;
});

$("#confirmDelete").addEventListener("click", async () => {
  if (!deleteTarget) return;
  const appName = deleteTarget;
  $("#deleteModal").style.display = "none";

  try {
    const res = await fetch(`/api/apps/${encodeURIComponent(appName)}`, {
      method: "DELETE",
    });
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    loadApps();
  } catch (err) {
    alert(`Fehler beim Löschen: ${err.message}`);
  }
  deleteTarget = null;
});

// Close modal on overlay click
$("#deleteModal").addEventListener("click", (e) => {
  if (e.target === $("#deleteModal")) {
    $("#deleteModal").style.display = "none";
    deleteTarget = null;
  }
});

// ----------------------------------------------------------
// Invalidate Cache
// ----------------------------------------------------------

window.invalidateApp = async function (appName, btn) {
  try {
    const res = await fetch(`/api/apps/${encodeURIComponent(appName)}/invalidate`, {
      method: "POST",
    });
    if (!res.ok) {
      const data = await res.json();
      alert(data.detail || "Fehler");
      return;
    }
    // Brief visual feedback
    if (btn) {
      btn.textContent = "✓";
      setTimeout(() => (btn.textContent = "↻"), 1500);
    }
  } catch (err) {
    alert(`Fehler: ${err.message}`);
  }
};

// ----------------------------------------------------------
// Helpers
// ----------------------------------------------------------

function escapeHtml(str) {
  const div = document.createElement("div");
  div.textContent = str;
  return div.innerHTML;
}

function humanSize(bytes) {
  const units = ["B", "KB", "MB", "GB"];
  let i = 0;
  while (bytes >= 1024 && i < units.length - 1) {
    bytes /= 1024;
    i++;
  }
  return bytes.toFixed(1) + " " + units[i];
}

// ----------------------------------------------------------
// Init
// ----------------------------------------------------------

loadApps();
