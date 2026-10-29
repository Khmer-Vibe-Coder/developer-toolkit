// Developer Toolkit Desktop Workbench — Electron Renderer Controller (Pure IPC)
const state = {
  version: '2.0.0',
  platform: 'darwin',
  callerDir: '',
  reportOutputDir: '',
  currentRepoName: '',
  repos: [],
  templates: [],
  selectedRepos: new Set(),
  repoFilter: '',
  activeTab: 'rebase',
  branchMode: 'develop',
  customBranch: '',
  perRepoBranches: {},
  datePreset: 'last-7-days',
  fromDate: '',
  toDate: '',
  authorMode: 'all',
  authorPattern: '',
  lastReportMarkdown: '',
  lastSavedFile: '',
  scannedCandidates: [],
  favoriteBranches: ['develop', 'main'],
};

function $(id) {
  return document.getElementById(id);
}

export function escapeHtml(value) {
  return String(value ?? '')
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

export function createDtkClientBridge(vscodeApi, eventTarget) {
  let seq = 0;
  const pending = new Map();

  eventTarget.addEventListener('message', (event) => {
    const data = event?.data;
    if (!data || data.type !== 'dtk:response' || !pending.has(data.requestId)) {
      return;
    }
    const { resolve, reject } = pending.get(data.requestId);
    pending.delete(data.requestId);
    if (data.ok) {
      resolve(data.result);
    } else {
      reject(new Error(data.error || 'RPC request failed'));
    }
  });

  return new Proxy(
    {},
    {
      get(_target, method) {
        return (payload = {}) =>
          new Promise((resolve, reject) => {
            const requestId = `req_${++seq}_${Date.now()}`;
            pending.set(requestId, { resolve, reject });
            vscodeApi.postMessage({
              type: 'dtk:invoke',
              requestId,
              method: String(method),
              payload,
            });
          });
      },
    }
  );
}

function showToast(message) {
  const region = $('toast-region');
  const el = document.createElement('div');
  el.className = 'toast';
  el.textContent = message;
  region.appendChild(el);
  setTimeout(() => el.remove(), 3200);
}

// Setup Light-Dismiss Fallback for <dialog closedby="any"> and Invoker Commands [commandfor]
function setupDialogFallbacks() {
  const dialog = $('link-repo-dialog');
  if (dialog && !('closedBy' in HTMLDialogElement.prototype)) {
    dialog.addEventListener('click', (event) => {
      if (event.target !== dialog) return;
      const rect = dialog.getBoundingClientRect();
      const isDialogContent =
        rect.top <= event.clientY &&
        event.clientY <= rect.top + rect.height &&
        rect.left <= event.clientX &&
        event.clientX <= rect.left + rect.width;
      if (isDialogContent) return;
      dialog.close();
    });
  }

  if (!('commandForElement' in HTMLButtonElement.prototype)) {
    document.addEventListener('click', (event) => {
      const button = event.target.closest?.('button[commandfor]');
      if (!button) return;
      const target = document.getElementById(button.getAttribute('commandfor'));
      const command = button.getAttribute('command');
      if (!target || !command) return;
      if (command === 'toggle-popover' && typeof target.togglePopover === 'function') {
        target.togglePopover();
      } else if (command === 'show-popover' && typeof target.showPopover === 'function') {
        target.showPopover();
      } else if (command === 'hide-popover' && typeof target.hidePopover === 'function') {
        target.hidePopover();
      }
    });
  }
}

// Setup Dark Mode Toggle following <meta name="color-scheme">
function setupThemeToggle() {
  const btn = $('btn-theme-toggle');
  const meta = document.querySelector('meta[name="color-scheme"]');
  if (!btn || !meta) return;

  btn.addEventListener('click', () => {
    const sysDark = window.matchMedia('(prefers-color-scheme: dark)').matches;
    const stored = localStorage.getItem('color-scheme');
    const currentRendered = stored === 'dark' || stored === 'light' ? stored : sysDark ? 'dark' : 'light';
    const target = currentRendered === 'dark' ? 'light' : 'dark';
    const currentSystem = sysDark ? 'dark' : 'light';

    if (target === currentSystem) {
      localStorage.removeItem('color-scheme');
      meta.content = 'light dark';
    } else {
      localStorage.setItem('color-scheme', target);
      meta.content = target;
    }
  });

  window.addEventListener('storage', (e) => {
    if (e.key === 'color-scheme') {
      meta.content = e.newValue ?? 'light dark';
    }
  });
}

function renderRepoRail() {
  const list = $('repo-list');
  const summary = $('repo-selection-summary');
  summary.textContent = `${state.selectedRepos.size} / ${state.repos.length}`;

  const q = state.repoFilter.toLowerCase().trim();
  const filtered = state.repos.filter(
    (r) => !q || r.name.toLowerCase().includes(q) || (r.currentBranch || '').toLowerCase().includes(q)
  );

  if (!filtered.length) {
    list.innerHTML = `<div class="section-sub" style="padding:12px;">${
      state.repos.length
        ? 'No repositories match your filter.'
        : 'No repositories linked yet. Click "+ Link / Scan Repos" to get started.'
    }</div>`;
    return;
  }

  list.innerHTML = '';
  for (const repo of filtered) {
    const isSelected = state.selectedRepos.has(repo.name);
    const card = document.createElement('div');
    card.className = `repo-card${isSelected ? ' selected' : ''}`;
    card.setAttribute('role', 'listitem');

    let statusClass = 'clean';
    let statusLabel = 'clean';
    if (!repo.exists) {
      statusClass = 'danger';
      statusLabel = 'missing';
    } else if (repo.rebasing) {
      statusClass = 'danger';
      statusLabel = 'rebasing';
    } else if (repo.dirtyCount > 0) {
      statusClass = 'dirty';
      statusLabel = `${repo.dirtyCount} uncommitted`;
    }

    const safeName = escapeHtml(repo.name);
    const safePath = escapeHtml(repo.path);
    const safeType = escapeHtml(repo.type);
    const safeBranch = escapeHtml(repo.currentBranch || 'HEAD');

    card.innerHTML = `
      <div class="repo-card-top">
        <label class="repo-check-label">
          <input type="checkbox" data-repo-check="${safeName}" ${isSelected ? 'checked' : ''}>
          <span class="repo-name-text" title="${safePath}">${safeName}</span>
        </label>
        ${repo.isCurrentWorkspace ? '<span class="pill pill-workspace" title="Currently open in IDE workspace">📍 workspace</span>' : ''}
        <span class="pill">${safeType}</span>
        <button type="button" class="btn-inline" data-open-repo="${safePath}" title="Open folder in OS file manager">📂</button>
        <button type="button" class="btn-inline" data-unlink-repo="${safeName}" title="Unlink ${safeName}">✕</button>
      </div>
      <div class="repo-meta-row">
        <span><span class="status-dot ${statusClass}"></span> ${escapeHtml(statusLabel)}</span>
        <span>·</span>
        <span>🌿 ${safeBranch}</span>
      </div>
    `;
    list.appendChild(card);
  }

  renderPerRepoBranchMatrix();
  renderRebaseTab();
}

function renderPerRepoBranchMatrix() {
  const container = $('per-repo-branch-matrix');
  if (state.branchMode !== 'PER_REPO') {
    container.classList.add('hidden');
    return;
  }
  container.classList.remove('hidden');
  const chosen = state.repos.filter((r) => state.selectedRepos.has(r.name));
  if (!chosen.length) {
    container.innerHTML = '<div class="section-sub">Select at least one repository on the left.</div>';
    return;
  }

  container.innerHTML = '';
  for (const repo of chosen) {
    const currentChoice = state.perRepoBranches[repo.name] || repo.currentBranch || 'develop';
    state.perRepoBranches[repo.name] = currentChoice;
    const branches = repo.branches.length ? repo.branches : ['develop', 'main', 'master'];
    const row = document.createElement('div');
    row.className = 'matrix-row';
    const optionsHtml = branches
      .map((b) => `<option value="${escapeHtml(b)}" ${b === currentChoice ? 'selected' : ''}>${escapeHtml(b)}</option>`)
      .join('');
    row.innerHTML = `
      <span>${escapeHtml(repo.name)}</span>
      <select class="select-compact" data-per-repo-select="${escapeHtml(repo.name)}">
        ${optionsHtml}
      </select>
    `;
    container.appendChild(row);
  }
}

function renderTemplates() {
  $('tpl-count-badge').textContent = String(state.templates.length);
  const quickSelect = $('quick-template-select');
  quickSelect.innerHTML = '<option value="">Custom configuration (no template)</option>';
  for (const tpl of state.templates) {
    const opt = document.createElement('option');
    opt.value = tpl.name;
    opt.textContent = `📋 ${tpl.name} (${tpl.repos.join(', ')})`;
    quickSelect.appendChild(opt);
  }

  const list = $('templates-list');
  if (!state.templates.length) {
    list.innerHTML =
      '<div class="template-card"><p class="section-sub">No templates saved yet. Configure a report in the Report Builder and click "Save Setup as Template".</p></div>';
    return;
  }

  list.innerHTML = '';
  for (const tpl of state.templates) {
    const card = document.createElement('div');
    card.className = 'template-card';
    const safeName = escapeHtml(tpl.name);
    const safeRepos = escapeHtml(tpl.repos.join(', ') || 'all');
    const safeBranch = escapeHtml(tpl.branchSpec);
    const safeAuthor = escapeHtml(`${tpl.authorMode}${tpl.authorPattern ? ` (${tpl.authorPattern})` : ''}`);
    const safeDate = escapeHtml(tpl.datePreset);
    card.innerHTML = `
      <div class="template-card-top">
        <strong>📋 ${safeName}</strong>
        <div class="topbar-actions">
          <button type="button" class="btn btn-primary btn-sm" data-run-tpl="${safeName}">Run &amp; Save Report</button>
          <button type="button" class="btn btn-secondary btn-sm" data-load-tpl="${safeName}">Load in Builder</button>
          <button type="button" class="btn btn-secondary btn-sm" data-edit-tpl="${safeName}">Edit</button>
          <button type="button" class="btn btn-ghost btn-sm" data-delete-tpl="${safeName}">Delete</button>
        </div>
      </div>
      <div class="template-meta">
        <span>Repos: ${safeRepos}</span>
        <span>Branch: ${safeBranch}</span>
        <span>Author: ${safeAuthor}</span>
        <span>Date: ${safeDate}</span>
      </div>
    `;
    list.appendChild(card);
  }
}

export function renderFavoriteBranchPills() {
  const container = $('rebase-favorite-pills');
  if (!container) return;

  const currentTarget =
    ($('rebase-custom-target') && $('rebase-custom-target').value.trim()) ||
    ($('rebase-target-select') && $('rebase-target-select').value) ||
    'develop';

  const favorites = Array.isArray(state.favoriteBranches) && state.favoriteBranches.length
    ? state.favoriteBranches
    : ['develop', 'main'];

  container.innerHTML = favorites
    .map((b) => {
      const safeBranch = escapeHtml(b);
      const isActive = b === currentTarget;
      return `<button type="button" class="favorite-pill${isActive ? ' active' : ''}" data-fav-branch="${safeBranch}" title="Select ${safeBranch} as base branch">
        <svg class="star-icon favorite-pill-star" viewBox="0 0 24 24" width="12" height="12" fill="currentColor" aria-hidden="true"><polygon points="12 2 15.09 8.26 22 9.27 17 14.14 18.18 21.02 12 17.77 5.82 21.02 7 14.14 2 9.27 8.91 8.26 12 2"/></svg>
        <span>${safeBranch}</span>
        <span class="favorite-pill-remove" data-remove-fav="${safeBranch}" title="Remove ${safeBranch} from favorites" aria-label="Remove ${safeBranch} from favorites">✕</span>
      </button>`;
    })
    .join('');

  const starBtn = $('btn-star-target-branch');
  if (starBtn) {
    const isStarred = favorites.includes(currentTarget);
    starBtn.classList.toggle('starred', isStarred);
    starBtn.title = isStarred
      ? `Remove '${currentTarget}' from favorite base branches`
      : `Add '${currentTarget}' to favorite base branches`;
    starBtn.setAttribute('aria-label', starBtn.title);
  }
}

export async function toggleFavoriteBranch(branchName) {
  const cleanBranch = String(branchName || '').trim();
  if (!cleanBranch) return;

  let favorites = Array.isArray(state.favoriteBranches) && state.favoriteBranches.length
    ? [...state.favoriteBranches]
    : ['develop', 'main'];

  const idx = favorites.indexOf(cleanBranch);
  if (idx >= 0) {
    favorites.splice(idx, 1);
    if (!favorites.length) favorites = ['develop', 'main'];
    showToast(`Removed '${cleanBranch}' from favorites`);
  } else {
    favorites.push(cleanBranch);
    showToast(`Added '${cleanBranch}' to favorite branches`);
  }

  state.favoriteBranches = Array.from(new Set(favorites.map((b) => b.trim()).filter(Boolean)));
  try {
    if (window.dtk?.saveGuiSettings) {
      await window.dtk.saveGuiSettings({ favoriteBranches: state.favoriteBranches });
    }
  } catch (err) {
    console.error('Failed to save favorite branches:', err);
  }

  renderRebaseTab();
}

function updateRebaseRouteBanner() {
  const repoSelect = $('rebase-repo-select');
  const targetSelect = $('rebase-target-select');
  const customInput = $('rebase-custom-target');
  const routeBanner = $('rebase-route-summary');
  if (!routeBanner) return;

  const localRepos = state.repos.filter((r) => r.type === 'local');
  const activeRepo = localRepos.find((r) => r.name === repoSelect.value) || localRepos[0];
  if (!activeRepo) {
    routeBanner.textContent = 'No local repository selected.';
    return;
  }

  const workingBranch = activeRepo.currentBranch || 'HEAD';
  const targetBranch = (customInput && customInput.value.trim()) || targetSelect.value || 'develop';

  if (workingBranch === targetBranch) {
    routeBanner.innerHTML = `⚠️ Working branch and target branch are both <strong>${escapeHtml(
      workingBranch
    )}</strong>. Select a base branch like <strong>develop</strong> or <strong>main</strong> to rebase onto (or running will simply <code>git pull origin ${escapeHtml(
      targetBranch
    )}</code>).`;
  } else {
    routeBanner.innerHTML = `☁️ Pulls latest from <strong>origin/${escapeHtml(
      targetBranch
    )}</strong> (local <code>${escapeHtml(
      targetBranch
    )}</code>) ➔ rebases your current branch <strong>🌿 ${escapeHtml(workingBranch)}</strong> on top of it.`;
  }

  renderFavoriteBranchPills();
}

function renderRebaseTab() {
  const repoSelect = $('rebase-repo-select');
  const targetSelect = $('rebase-target-select');
  const telemetry = $('rebase-repo-telemetry');
  const abortBtn = $('btn-abort-rebase');

  const localRepos = state.repos.filter((r) => r.type === 'local');
  if (!localRepos.length) {
    repoSelect.innerHTML = '<option value="">No local repositories linked</option>';
    targetSelect.innerHTML = '<option value="develop">develop</option>';
    telemetry.textContent = 'Link a local repository to run git-smart-rebase.';
    updateRebaseRouteBanner();
    return;
  }

  const prevRepo = repoSelect.value || state.currentRepoName || localRepos[0].name;
  repoSelect.innerHTML = localRepos
    .map(
      (r) =>
        `<option value="${escapeHtml(r.name)}" title="${escapeHtml(r.path)}" ${r.name === prevRepo ? 'selected' : ''}>${escapeHtml(r.name)}</option>`
    )
    .join('');

  const activeRepo = localRepos.find((r) => r.name === repoSelect.value) || localRepos[0];
  repoSelect.title = activeRepo ? activeRepo.path : '';
  
  const favorites = Array.isArray(state.favoriteBranches) && state.favoriteBranches.length
    ? state.favoriteBranches
    : ['develop', 'main'];

  const allBranches = Array.from(new Set([...favorites, ...activeRepo.branches]));

  const preferredOrder = ['develop', 'main', 'master', 'staging'];
  const prevTarget = targetSelect.value;
  const defaultTarget =
    (prevTarget && allBranches.includes(prevTarget) && prevTarget) ||
    favorites.find((b) => b !== activeRepo.currentBranch) ||
    preferredOrder.find((b) => allBranches.includes(b) && b !== activeRepo.currentBranch) ||
    allBranches.find((b) => b !== activeRepo.currentBranch) ||
    'develop';

  const favBranches = allBranches.filter((b) => favorites.includes(b));
  const otherBranches = allBranches.filter((b) => !favorites.includes(b));

  const buildOption = (b, isFav = false) => {
    let label = b;
    if (isFav) {
      label = `★ ${b}`;
    } else if (b === activeRepo.currentBranch) {
      label = `${b} (current)`;
    }
    return `<option value="${escapeHtml(b)}" ${b === defaultTarget ? 'selected' : ''}>${escapeHtml(label)}</option>`;
  };

  let optionsHtml = '';
  if (favBranches.length) {
    optionsHtml += `<optgroup label="★ Favorite Base Branches">${favBranches.map((b) => buildOption(b, true)).join('')}</optgroup>`;
  }
  if (otherBranches.length) {
    optionsHtml += `<optgroup label="Other Repository Branches">${otherBranches.map((b) => buildOption(b, false)).join('')}</optgroup>`;
  }
  targetSelect.innerHTML = optionsHtml || allBranches.map((b) => buildOption(b)).join('');

  telemetry.textContent = `Your current working branch: ${activeRepo.currentBranch || 'HEAD'} · Working tree: ${
    activeRepo.dirtyCount > 0
      ? `${activeRepo.dirtyCount} uncommitted file(s) (will auto-stash)`
      : 'clean (no stash needed)'
  }`;

  if (activeRepo.rebasing) {
    abortBtn.classList.remove('hidden');
  } else {
    abortBtn.classList.add('hidden');
  }
  updateRebaseRouteBanner();
}

function computeBranchSpecFromUI() {
  if (state.branchMode === 'CUSTOM') {
    return $('custom-branch-input').value.trim() || 'develop';
  }
  if (state.branchMode === 'PER_REPO') {
    const pairs = [];
    for (const rName of state.selectedRepos) {
      pairs.push(`${rName}:${state.perRepoBranches[rName] || 'develop'}`);
    }
    return pairs.join(',');
  }
  return state.branchMode || 'develop';
}

function applyTemplateToBuilder(tplName) {
  const tpl = state.templates.find((t) => t.name === tplName);
  if (!tpl) return;

  state.selectedRepos = new Set(tpl.repos);
  if (tpl.branchSpec.includes(':')) {
    state.branchMode = 'PER_REPO';
    state.perRepoBranches = {};
    for (const pair of tpl.branchSpec.split(',')) {
      const [rn, rb] = pair.split(':');
      if (rn && rb) state.perRepoBranches[rn.trim()] = rb.trim();
    }
  } else if (['develop', 'main', 'master', 'staging', 'CURRENT'].includes(tpl.branchSpec)) {
    state.branchMode = tpl.branchSpec;
  } else {
    state.branchMode = 'CUSTOM';
    $('custom-branch-input').value = tpl.branchSpec;
  }

  for (const btn of document.querySelectorAll('#branch-mode-pills .choice-pill')) {
    btn.classList.toggle('active', btn.dataset.branch === state.branchMode);
  }
  $('custom-branch-row').classList.toggle('hidden', state.branchMode !== 'CUSTOM');

  state.authorMode = tpl.authorMode || 'all';
  state.authorPattern = tpl.authorPattern || '';
  $('custom-author-input').value = state.authorPattern;
  for (const btn of document.querySelectorAll('#author-mode-pills .choice-pill')) {
    btn.classList.toggle('active', btn.dataset.author === state.authorMode);
  }
  $('custom-author-row').classList.toggle('hidden', state.authorMode !== 'custom');

  if (tpl.datePreset && tpl.datePreset !== 'ask') {
    state.datePreset = tpl.datePreset;
    for (const btn of document.querySelectorAll('#date-preset-pills .choice-pill')) {
      btn.classList.toggle('active', btn.dataset.preset === state.datePreset);
    }
    $('custom-date-row').classList.toggle('hidden', state.datePreset !== 'custom');
  }

  renderRepoRail();
}

async function runReport() {
  if (!state.selectedRepos.size) {
    showToast('Select at least one repository in the left rail.');
    return;
  }

  const btn = $('btn-generate-report');
  btn.disabled = true;
  btn.textContent = 'Generating Report...';
  $('inspector-title').textContent = 'Live Report Inspector';
  const stats = $('inspector-stats');
  stats.className = 'pill pill-running';
  stats.textContent = 'Running...';

  try {
    const res = await window.dtk.generateReport({
      repos: Array.from(state.selectedRepos),
      branchSpec: computeBranchSpecFromUI(),
      preset: state.datePreset === 'custom' ? '' : state.datePreset,
      fromDate: state.datePreset === 'custom' ? $('report-from-date').value : '',
      toDate: state.datePreset === 'custom' ? $('report-to-date').value : '',
      authorMode: state.authorMode,
      authorPattern: $('custom-author-input').value.trim(),
      doFetch: $('opt-fetch').checked,
      detailed: $('opt-detailed').checked,
      includeMerges: $('opt-merges').checked,
      saveToDisk: true,
    });

    state.lastReportMarkdown = res.markdown;
    state.lastSavedFile = res.savedFile || '';
    $('live-inspector').classList.add('has-output');
    $('inspector-output').textContent = res.markdown;
    stats.className = 'pill pill-success';
    stats.textContent = `${res.totalCommits} commit(s) · ${res.repoCount} repo(s)`;
    $('btn-copy-output').disabled = false;

    if (res.savedFile) {
      $('saved-file-banner').classList.remove('hidden');
      $('saved-file-text').textContent = `Saved: ${res.savedFile}`;
    }
    showToast(`Report generated (${res.totalCommits} commits)`);
  } catch (err) {
    showToast(err.message);
    stats.className = 'pill pill-danger';
    stats.textContent = 'Error';
  } finally {
    btn.disabled = false;
    btn.textContent = 'Generate & Save Report (⌘↵)';
  }
}

async function refreshState(dataOverride = null) {
  const data = dataOverride || (await window.dtk.getState());
  state.version = data.version;
  state.platform = data.platform || 'darwin';
  state.callerDir = data.callerDir;
  state.reportOutputDir = data.reportOutputDir || '';
  state.favoriteBranches = Array.isArray(data.favoriteBranches) && data.favoriteBranches.length
    ? data.favoriteBranches
    : ['develop', 'main'];
  state.currentRepoName = data.currentRepoName;
  state.repos = data.repos || [];
  state.templates = data.templates || [];

  document.documentElement.classList.add(`platform-${state.platform}`);

  if (state.selectedRepos.size === 0 && state.repos.length > 0) {
    for (const r of state.repos) state.selectedRepos.add(r.name);
  }

  // Auto-check active workspace repo without clearing existing selections
  if (state.currentRepoName) {
    state.selectedRepos.add(state.currentRepoName);
  }

  $('version-badge').textContent = `v${state.version}`;
  $('caller-path').textContent = state.callerDir;
  if ($('output-dir-label')) {
    $('output-dir-label').textContent = state.reportOutputDir;
  }
  if (!$('scan-dir-input').value) {
    $('scan-dir-input').value = state.callerDir;
  }

  renderRepoRail();
  renderTemplates();
  renderRebaseTab();

  document.body.dataset.activeTab = state.activeTab;
  for (const b of document.querySelectorAll('.mode-tab')) {
    const active = b.dataset.tab === state.activeTab;
    b.classList.toggle('active', active);
    b.setAttribute('aria-selected', String(active));
  }
  $('panel-report').classList.toggle('hidden', state.activeTab !== 'report');
  $('panel-templates').classList.toggle('hidden', state.activeTab !== 'templates');
  $('panel-rebase').classList.toggle('hidden', state.activeTab !== 'rebase');
}

function bindEvents() {
  // Mode Tabs
  for (const tabBtn of document.querySelectorAll('.mode-tab')) {
    tabBtn.addEventListener('click', () => {
      state.activeTab = tabBtn.dataset.tab;
      document.body.dataset.activeTab = state.activeTab;
      for (const b of document.querySelectorAll('.mode-tab')) {
        const active = b.dataset.tab === state.activeTab;
        b.classList.toggle('active', active);
        b.setAttribute('aria-selected', String(active));
      }
      $('panel-report').classList.toggle('hidden', state.activeTab !== 'report');
      $('panel-templates').classList.toggle('hidden', state.activeTab !== 'templates');
      $('panel-rebase').classList.toggle('hidden', state.activeTab !== 'rebase');
      if (state.activeTab === 'rebase') {
        renderRebaseTab();
      }
    });
  }

  // Repo Rail Events
  $('repo-list').addEventListener('change', (e) => {
    const repoName = e.target.dataset.repoCheck;
    if (!repoName) return;
    if (e.target.checked) {
      state.selectedRepos.add(repoName);
    } else {
      state.selectedRepos.delete(repoName);
    }
    renderRepoRail();
  });

  $('repo-list').addEventListener('click', async (e) => {
    const openPathTarget = e.target.dataset.openRepo;
    if (openPathTarget) {
      await window.dtk.openPath({ targetPath: openPathTarget });
      return;
    }

    const unlinkName = e.target.dataset.unlinkRepo;
    if (!unlinkName) return;
    await window.dtk.removeRepos({ names: [unlinkName] });
    state.selectedRepos.delete(unlinkName);
    await refreshState();
    showToast(`Unlinked ${unlinkName}`);
  });

  $('btn-select-all-repos').addEventListener('click', () => {
    for (const r of state.repos) state.selectedRepos.add(r.name);
    renderRepoRail();
  });

  $('btn-clear-all-repos').addEventListener('click', () => {
    state.selectedRepos.clear();
    renderRepoRail();
  });

  $('repo-search-input').addEventListener('input', (e) => {
    state.repoFilter = e.target.value;
    renderRepoRail();
  });

  // Per-repo branch matrix change
  $('per-repo-branch-matrix').addEventListener('change', (e) => {
    const rName = e.target.dataset.perRepoSelect;
    if (rName) {
      state.perRepoBranches[rName] = e.target.value;
    }
  });

  // Branch Mode Pills
  $('branch-mode-pills').addEventListener('click', (e) => {
    const btn = e.target.closest('.choice-pill');
    if (!btn) return;
    state.branchMode = btn.dataset.branch;
    for (const b of document.querySelectorAll('#branch-mode-pills .choice-pill')) {
      b.classList.toggle('active', b === btn);
    }
    $('custom-branch-row').classList.toggle('hidden', state.branchMode !== 'CUSTOM');
    renderPerRepoBranchMatrix();
  });

  // Date Preset Pills
  $('date-preset-pills').addEventListener('click', (e) => {
    const btn = e.target.closest('.choice-pill');
    if (!btn) return;
    state.datePreset = btn.dataset.preset;
    for (const b of document.querySelectorAll('#date-preset-pills .choice-pill')) {
      b.classList.toggle('active', b === btn);
    }
    $('resolved-date-hint').textContent = btn.textContent;
    $('custom-date-row').classList.toggle('hidden', state.datePreset !== 'custom');
  });

  // Author Mode Pills
  $('author-mode-pills').addEventListener('click', (e) => {
    const btn = e.target.closest('.choice-pill');
    if (!btn) return;
    state.authorMode = btn.dataset.author;
    for (const b of document.querySelectorAll('#author-mode-pills .choice-pill')) {
      b.classList.toggle('active', b === btn);
    }
    $('custom-author-row').classList.toggle('hidden', state.authorMode !== 'custom');
  });

  // Quick Template Select
  $('quick-template-select').addEventListener('change', (e) => {
    if (e.target.value) {
      applyTemplateToBuilder(e.target.value);
      showToast(`Loaded template '${e.target.value}'`);
    }
  });

  // Submit Report
  $('report-form').addEventListener('submit', (e) => {
    e.preventDefault();
    runReport();
  });

  // Copy Output (Report or Rebase Telemetry)
  $('btn-copy-output').addEventListener('click', async () => {
    const text = state.lastReportMarkdown || $('inspector-output').textContent;
    if (!text) return;
    await navigator.clipboard.writeText(text);
    const btn = $('btn-copy-output');
    btn.textContent = 'Copied!';
    setTimeout(() => {
      btn.textContent = 'Copy Output';
    }, 1500);
  });

  // Clear Inspector Output
  $('btn-clear-output').addEventListener('click', () => {
    $('inspector-output').textContent = 'Inspector output cleared. Run Smart Rebase or Generate Report to view live output.';
    $('live-inspector').classList.remove('has-output');
    const stats = $('inspector-stats');
    stats.className = 'pill';
    stats.textContent = 'Ready';
    $('btn-copy-output').disabled = true;
    $('saved-file-banner').classList.add('hidden');
    state.lastReportMarkdown = '';
    showToast('Inspector output cleared');
  });

  // Output Folder Picker & Reveal Saved Report
  $('btn-change-output-dir').addEventListener('click', async () => {
    const res = await window.dtk.pickReportOutputDir();
    if (!res.canceled && res.reportOutputDir) {
      state.reportOutputDir = res.reportOutputDir;
      $('output-dir-label').textContent = res.reportOutputDir;
      showToast(`Output folder set to ${res.reportOutputDir}`);
    }
  });

  $('btn-reveal-report').addEventListener('click', async () => {
    if (!state.lastSavedFile) return;
    await window.dtk.revealInFolder({ targetPath: state.lastSavedFile });
  });

  // Save as Template Flow
  const openTplEditor = () => {
    document.querySelector('[data-tab="templates"]').click();
    $('template-editor-box').classList.remove('hidden');
    $('tpl-name-input').focus();
  };
  $('btn-save-as-template').addEventListener('click', openTplEditor);
  $('btn-new-template-From-current').addEventListener('click', openTplEditor);
  $('btn-cancel-save-template').addEventListener('click', () => {
    $('template-editor-box').classList.add('hidden');
  });

  $('btn-confirm-save-template').addEventListener('click', async () => {
    const name = $('tpl-name-input').value.trim();
    if (!name) {
      showToast('Enter a template name.');
      return;
    }
    await window.dtk.saveTemplate({
      name,
      repos: Array.from(state.selectedRepos),
      branchSpec: computeBranchSpecFromUI(),
      authorMode: state.authorMode,
      authorPattern: $('custom-author-input').value.trim(),
      datePreset: $('tpl-default-date').value,
    });
    $('template-editor-box').classList.add('hidden');
    $('tpl-name-input').value = '';
    await refreshState();
    showToast(`Saved template '${name}'`);
  });

  // Template List Actions
  $('templates-list').addEventListener('click', async (e) => {
    const runName = e.target.dataset.runTpl;
    const loadName = e.target.dataset.loadTpl;
    const editName = e.target.dataset.editTpl;
    const delName = e.target.dataset.deleteTpl;

    if (runName) {
      applyTemplateToBuilder(runName);
      document.querySelector('[data-tab="report"]').click();
      await runReport();
    } else if (loadName) {
      applyTemplateToBuilder(loadName);
      document.querySelector('[data-tab="report"]').click();
      showToast(`Loaded '${loadName}' into Report Builder`);
    } else if (editName) {
      const tpl = state.templates.find((t) => t.name === editName);
      if (tpl) {
        applyTemplateToBuilder(editName);
        $('template-editor-box').classList.remove('hidden');
        $('tpl-name-input').value = tpl.name;
        $('tpl-default-date').value = tpl.datePreset || 'ask';
        $('tpl-name-input').focus();
      }
    } else if (delName) {
      await window.dtk.removeTemplates({ names: [delName] });
      await refreshState();
      showToast(`Deleted template '${delName}'`);
    }
  });

  // Smart Rebase Events
  $('rebase-repo-select').addEventListener('change', renderRebaseTab);
  $('rebase-target-select').addEventListener('change', () => {
    if ($('rebase-custom-target')) $('rebase-custom-target').value = '';
    updateRebaseRouteBanner();
  });
  $('rebase-custom-target').addEventListener('input', updateRebaseRouteBanner);

  // Favorite Base Branch Pills
  $('rebase-favorite-pills').addEventListener('click', (e) => {
    const removeBtn = e.target.closest('[data-remove-fav]');
    if (removeBtn) {
      e.stopPropagation();
      const branchToRemove = removeBtn.dataset.removeFav;
      toggleFavoriteBranch(branchToRemove);
      return;
    }

    const pillBtn = e.target.closest('.favorite-pill');
    if (!pillBtn) return;
    const branch = pillBtn.dataset.favBranch;
    if (!branch) return;

    if ($('rebase-custom-target')) $('rebase-custom-target').value = '';
    const targetSelect = $('rebase-target-select');
    if (targetSelect) {
      let optionExists = Array.from(targetSelect.options).some((opt) => opt.value === branch);
      if (!optionExists) {
        const newOpt = document.createElement('option');
        newOpt.value = branch;
        newOpt.textContent = `★ ${branch}`;
        targetSelect.appendChild(newOpt);
      }
      targetSelect.value = branch;
    }
    updateRebaseRouteBanner();
  });

  // Star Button toggle
  $('btn-star-target-branch').addEventListener('click', () => {
    const customVal = $('rebase-custom-target')?.value.trim();
    const selectVal = $('rebase-target-select')?.value;
    const branchToToggle = customVal || selectVal || 'develop';
    toggleFavoriteBranch(branchToToggle);
  });

  $('rebase-form').addEventListener('submit', async (e) => {
    e.preventDefault();
    const repoName = $('rebase-repo-select').value;
    const targetBranch = $('rebase-custom-target').value.trim() || $('rebase-target-select').value || 'develop';
    if (!repoName) return;

    const btn = $('btn-run-rebase');
    btn.disabled = true;
    btn.textContent = 'Rebasing...';

    const startTime = Date.now();
    const startTimeStr = new Date().toLocaleTimeString();

    $('inspector-title').textContent = 'Smart Rebase Telemetry';
    const statsBadge = $('inspector-stats');
    statsBadge.className = 'pill pill-running';
    statsBadge.textContent = 'Running...';
    statsBadge.title = `Started at ${startTimeStr}`;

    $('live-inspector').classList.add('has-output');
    $('saved-file-banner').classList.add('hidden');
    $('btn-copy-output').disabled = false;

    // Instant reset so the user can clearly see a fresh run has started
    $('inspector-output').textContent =
      `[${startTimeStr}] ⏳ Initiating Smart Rebase Pipeline...\n` +
      `Repository  : ${repoName}\n` +
      `Base Branch : ${targetBranch}\n\n` +
      `Executing safety stages:\n` +
      `  1. Auto-Stashing pending changes\n` +
      `  2. Synchronizing base branch with origin\n` +
      `  3. Rebasing working commits onto target\n` +
      `  4. Restoring auto-stashed changes\n\n` +
      `Please wait...`;

    try {
      const res = await window.dtk.runRebase({ repoName, targetBranch });
      const durationMs = Date.now() - startTime;
      const finishTimeStr = new Date().toLocaleTimeString();
      const durStr = durationMs >= 1000 ? `${(durationMs / 1000).toFixed(1)}s` : `${durationMs}ms`;

      const logLines = (res.steps || []).map((s, idx) => {
        const icon = s.status === 'done' ? '✔' : s.status === 'skipped' ? '•' : '✖';
        return `${idx + 1}. [${icon}] ${s.step}\n   ${s.detail}`;
      });

      let statusLabel = '✔ COMPLETED';
      let outcomeDesc = `Rebased ${res.currentBranch || 'branch'} onto ${res.targetBranch || targetBranch} cleanly`;
      let pillClass = 'pill pill-success';
      let pillText = `✔ Completed (${durStr})`;

      if (res.conflict) {
        statusLabel = '⚠ CONFLICT DETECTED';
        outcomeDesc = 'Rebase paused due to merge conflict. Resolve conflicts or click Abort.';
        pillClass = 'pill pill-warning';
        pillText = `⚠ Conflict (${durStr})`;
        $('btn-abort-rebase').classList.remove('hidden');
        showToast('Rebase conflict detected — resolve or click Abort Rebase');
      } else if (res.ok) {
        $('btn-abort-rebase').classList.add('hidden');
        showToast(`Rebased ${res.currentBranch} onto ${res.targetBranch} (${durStr})`);
      } else {
        statusLabel = '✖ FAILED';
        outcomeDesc = res.error || 'Smart rebase pipeline failed';
        pillClass = 'pill pill-danger';
        pillText = `✖ Failed (${durStr})`;
        showToast(res.error || 'Smart rebase failed');
      }

      const banner = [
        '═'.repeat(64),
        `SMART REBASE TELEMETRY · ${statusLabel}`,
        `Timestamp   : ${finishTimeStr} (duration: ${durationMs}ms)`,
        `Repository  : ${repoName}`,
        `Base Branch : origin/${targetBranch}`,
        `Outcome     : ${outcomeDesc}`,
        '═'.repeat(64),
      ].join('\n');

      statsBadge.className = pillClass;
      statsBadge.textContent = pillText;
      statsBadge.title = `Finished at ${finishTimeStr} (duration: ${durationMs}ms)`;
      $('inspector-output').textContent = `${banner}\n\n${logLines.join('\n\n')}`;

      await refreshState();
    } catch (err) {
      statsBadge.className = 'pill pill-danger';
      statsBadge.textContent = '✖ Error';
      $('inspector-output').textContent += `\n\n✖ Exception: ${err.message}`;
      showToast(err.message);
    } finally {
      btn.disabled = false;
      btn.textContent = 'Run Smart Rebase';
    }
  });

  $('btn-abort-rebase').addEventListener('click', async () => {
    const repoName = $('rebase-repo-select').value;
    if (!repoName) return;
    const timeStr = new Date().toLocaleTimeString();
    const res = await window.dtk.abortRebase({ repoName });

    const banner = [
      '═'.repeat(64),
      `SMART REBASE · ✖ ABORTED & RESTORED`,
      `Timestamp   : ${timeStr}`,
      `Repository  : ${repoName}`,
      `Outcome     : Rebase aborted, working tree restored from auto-stash`,
      '═'.repeat(64),
    ].join('\n');

    $('live-inspector').classList.add('has-output');
    $('inspector-output').textContent = `${banner}\n\n✔ ${res.message}`;
    const statsBadge = $('inspector-stats');
    statsBadge.className = 'pill pill-warning';
    statsBadge.textContent = `Aborted (${timeStr})`;
    await refreshState();
    showToast(res.message);
  });

  // Modal Dialog Open/Close & Scan/Add with Native OS Folder Pickers
  const dialog = $('link-repo-dialog');
  $('btn-open-link-modal').addEventListener('click', () => dialog.showModal());
  $('btn-rail-scan').addEventListener('click', () => dialog.showModal());
  $('btn-close-dialog').addEventListener('click', () => dialog.close());
  $('btn-refresh-state').addEventListener('click', () => {
    refreshState().then(() => showToast('Refreshed repository telemetry'));
  });

  $('btn-browse-scan-dir').addEventListener('click', async () => {
    const res = await window.dtk.pickFolder({
      title: 'Select Workspace Folder to Scan for Git Repositories',
      defaultPath: $('scan-dir-input').value.trim() || state.callerDir,
    });
    if (!res.canceled && res.folderPath) {
      $('scan-dir-input').value = res.folderPath;
      $('btn-run-scan').click();
    }
  });

  $('btn-browse-repo-dir').addEventListener('click', async () => {
    const res = await window.dtk.pickFolder({
      title: 'Select Local Git Repository Folder',
      defaultPath: state.callerDir,
    });
    if (!res.canceled && res.folderPath) {
      $('add-target-input').value = res.folderPath;
    }
  });

  $('btn-run-scan').addEventListener('click', async () => {
    const scanDir = $('scan-dir-input').value.trim();
    try {
      const res = await window.dtk.scanWorkspace({ scanDir, linkAll: false });
      state.scannedCandidates = res.candidates || [];
      const container = $('scan-results-container');
      const list = $('scan-candidates-list');
      container.classList.remove('hidden');

      if (!state.scannedCandidates.length) {
        list.innerHTML = '<div class="section-sub">No Git repositories found in that folder.</div>';
        return;
      }
      list.innerHTML = state.scannedCandidates
        .map(
          (c, i) => `
          <label class="checkbox-row">
            <input type="checkbox" data-scan-idx="${i}" ${c.alreadyLinked ? '' : 'checked'}>
            <span><strong>${escapeHtml(c.name)}</strong> <small class="field-hint">${escapeHtml(c.path)} ${
            c.alreadyLinked ? '(already linked)' : ''
          }</small></span>
          </label>`
        )
        .join('');
    } catch (err) {
      showToast(err.message);
    }
  });

  $('btn-link-scanned').addEventListener('click', async () => {
    const checks = document.querySelectorAll('[data-scan-idx]:checked');
    const chosen = Array.from(checks).map((el) => state.scannedCandidates[Number(el.dataset.scanIdx)]);
    if (!chosen.length) {
      showToast('Check at least one repository to link.');
      return;
    }
    await window.dtk.linkBatchRepos({ repos: chosen });
    for (const c of chosen) state.selectedRepos.add(c.name);
    dialog.close();
    await refreshState();
    showToast(`Linked ${chosen.length} repository(s)`);
  });

  $('btn-add-single-repo').addEventListener('click', async () => {
    const target = $('add-target-input').value.trim();
    const name = $('add-alias-input').value.trim();
    if (!target) {
      showToast('Enter a local folder path or remote Git URL.');
      return;
    }
    try {
      const res = await window.dtk.addRepo({ target, name });
      state.selectedRepos.add(res.linked.name);
      $('add-target-input').value = '';
      $('add-alias-input').value = '';
      dialog.close();
      await refreshState();
      showToast(`Linked '${res.linked.name}'`);
    } catch (err) {
      showToast(err.message);
    }
  });

  // Global Keyboard Shortcuts
  window.addEventListener('keydown', (e) => {
    if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === 'k') {
      e.preventDefault();
      $('repo-search-input').focus();
    } else if ((e.metaKey || e.ctrlKey) && e.key === 'Enter') {
      if (state.activeTab === 'report') {
        e.preventDefault();
        runReport();
      }
    }
  });
  // Real-time Workspace Sync Listener from host extension
  window.addEventListener('message', async (event) => {
    const msg = event?.data;
    if (msg && msg.type === 'dtk:activeRepoChanged' && msg.callerDir) {
      try {
        if (window.dtk?.syncWorkspaceRepo) {
          const updated = await window.dtk.syncWorkspaceRepo({ callerDir: msg.callerDir });
          await refreshState(updated);
        }
      } catch (err) {
        console.error('Failed to sync active workspace repo:', err);
      }
    }
  });
}

if (typeof document !== 'undefined') {
  if (!window.dtk && typeof acquireVsCodeApi === 'function') {
    window.dtk = createDtkClientBridge(acquireVsCodeApi(), window);
  }
  setupDialogFallbacks();
  setupThemeToggle();
  bindEvents();
  refreshState();
}
