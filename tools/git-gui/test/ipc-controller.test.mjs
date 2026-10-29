import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import os from 'node:os';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { loadGuiSettings, saveGuiSettings } from '../lib/config-store.mjs';
import { createIpcHandlers } from '../lib/ipc-controller.mjs';
import { escapeHtml } from '../public/app.mjs';

const execFileAsync = promisify(execFile);

async function initTempRepo(dir, branch = 'develop') {
  await fs.mkdir(dir, { recursive: true });
  await execFileAsync('git', ['init', '-b', branch], { cwd: dir });
  await execFileAsync('git', ['config', 'user.name', 'Test Dev'], { cwd: dir });
  await execFileAsync('git', ['config', 'user.email', 'dev@example.com'], { cwd: dir });
  await fs.writeFile(path.join(dir, 'README.md'), '# hello\n', 'utf8');
  await execFileAsync('git', ['add', '.'], { cwd: dir });
  await execFileAsync('git', ['commit', '-m', 'feat: initial desktop commit\n\n- added desktop support'], { cwd: dir });
}

test('resolves default reportOutputDir for terminal vs OS Dock launch and persists custom folder', async () => {
  const cfgDir = await fs.mkdtemp(path.join(os.tmpdir(), 'dtk-gui-settings-'));

  // When launched from OS Applications (callerDir = '/')
  const dockSettings = await loadGuiSettings(cfgDir, '/');
  assert.equal(dockSettings.reportOutputDir, path.join(os.homedir(), 'Documents', 'DeveloperToolkit-Reports'));

  // When launched from a project terminal (callerDir = '/tmp/my-project')
  const cliSettings = await loadGuiSettings(cfgDir, '/tmp/my-project');
  assert.equal(cliSettings.reportOutputDir, '/tmp/my-project/report');

  // When user picks a custom output folder
  const saved = await saveGuiSettings(cfgDir, { reportOutputDir: '/tmp/custom-reports' });
  assert.equal(saved.reportOutputDir, '/tmp/custom-reports');
  const reloaded = await loadGuiSettings(cfgDir, '/tmp/my-project');
  assert.equal(reloaded.reportOutputDir, '/tmp/custom-reports');
});

test('IPC handlers manage repos, templates, reports, native folder pickers, and shell reveal', async () => {
  const configDir = await fs.mkdtemp(path.join(os.tmpdir(), 'dtk-ipc-cfg-'));
  const callerDir = await fs.mkdtemp(path.join(os.tmpdir(), 'dtk-ipc-call-'));
  const demoRepo = path.join(callerDir, 'desktop-repo');
  await initTempRepo(demoRepo, 'develop');

  let revealedPath = '';
  let dialogCancelled = false;

  const mockDialog = {
    async showOpenDialog() {
      if (dialogCancelled) return { canceled: true, filePaths: [] };
      return { canceled: false, filePaths: [demoRepo] };
    },
  };
  const mockShell = {
    showItemInFolder(p) {
      revealedPath = p;
    },
    async openPath(p) {
      revealedPath = p;
      return '';
    },
  };

  const ipc = createIpcHandlers({
    configDir,
    callerDir,
    dialogApi: mockDialog,
    shellApi: mockShell,
  });

  // 1. Initial state
  const initialState = await ipc.getState();
  assert.deepEqual(initialState.repos, []);
  assert.equal(initialState.reportOutputDir, path.join(callerDir, 'report'));
  assert.deepEqual(initialState.favoriteBranches, ['develop', 'main']);

  // 1b. Save GUI settings (favorite branches)
  const savedSettings = await ipc.saveGuiSettings({
    favoriteBranches: ['develop', 'main', 'staging'],
  });
  assert.deepEqual(savedSettings.favoriteBranches, ['develop', 'main', 'staging']);
  const afterSettings = await ipc.getState();
  assert.deepEqual(afterSettings.favoriteBranches, ['develop', 'main', 'staging']);

  // 2. Native folder picker (active vs canceled)
  const picked = await ipc.pickFolder({});
  assert.equal(picked.canceled, false);
  assert.equal(picked.folderPath, demoRepo);

  dialogCancelled = true;
  const canceledPick = await ipc.pickFolder({});
  assert.equal(canceledPick.canceled, true);

  // 3. Add repo via IPC
  const added = await ipc.addRepo({ target: demoRepo });
  assert.equal(added.repos.length, 1);
  assert.equal(added.repos[0].name, 'desktop-repo');

  // 4. Save template via IPC
  const tplRes = await ipc.saveTemplate({
    name: 'desktop-weekly',
    repos: ['desktop-repo'],
    branchSpec: 'develop',
    authorMode: 'all',
    authorPattern: '',
    datePreset: 'today',
  });
  assert.equal(tplRes.templates.length, 1);

  // 5. Generate report via IPC & reveal saved file in OS file manager
  const reportRes = await ipc.generateReport({
    repos: ['desktop-repo'],
    branchSpec: 'develop',
    preset: 'today',
    authorMode: 'all',
  });
  assert.equal(reportRes.totalCommits, 1);
  assert.ok(reportRes.savedFile.startsWith(path.join(callerDir, 'report')));

  await ipc.revealInFolder({ targetPath: reportRes.savedFile });
  assert.equal(revealedPath, reportRes.savedFile);

  // 6. Test favorite branches updates via IPC
  const updatedSettings = await ipc.saveGuiSettings({
    favoriteBranches: ['develop', 'staging', 'release/v2'],
  });
  assert.deepEqual(updatedSettings.favoriteBranches, ['develop', 'staging', 'release/v2']);

  const nextState = await ipc.getState();
  assert.deepEqual(nextState.favoriteBranches, ['develop', 'staging', 'release/v2']);
});

test('package.json, main.mjs, and preload.cjs configure cross-platform Electron desktop app and IPC channels', async () => {
  const guiRoot = path.resolve(path.dirname(new URL(import.meta.url).pathname), '..');
  const pkg = JSON.parse(await fs.readFile(path.join(guiRoot, 'package.json'), 'utf8'));
  assert.equal(pkg.main, 'main.mjs');
  assert.ok(pkg.scripts['dist:mac']);
  assert.ok(pkg.scripts['dist:win']);
  assert.ok(pkg.scripts['dist:linux']);

  const mainSrc = await fs.readFile(path.join(guiRoot, 'main.mjs'), 'utf8');
  const preloadSrc = await fs.readFile(path.join(guiRoot, 'preload.cjs'), 'utf8');

  // Verify window can be resized to a thin companion width (minWidth: 360)
  assert.match(mainSrc, /minWidth:\s*360/);

  for (const method of [
    'getState',
    'syncWorkspaceRepo',
    'addRepo',
    'scanWorkspace',
    'linkBatchRepos',
    'removeRepos',
    'saveTemplate',
    'removeTemplates',
    'generateReport',
    'runRebase',
    'abortRebase',
    'pickFolder',
    'pickReportOutputDir',
    'saveGuiSettings',
    'revealInFolder',
    'openPath',
  ]) {
    assert.match(mainSrc, new RegExp(`dtk:${method}`));
    assert.match(preloadSrc, new RegExp(`dtk:${method}`));
  }
});

test('desktop renderer index.html and app.mjs use relative assets, window.dtk IPC, and native folder pickers', async () => {
  const guiRoot = path.resolve(path.dirname(new URL(import.meta.url).pathname), '..');
  const html = await fs.readFile(path.join(guiRoot, 'public', 'index.html'), 'utf8');
  const css = await fs.readFile(path.join(guiRoot, 'public', 'styles.css'), 'utf8');
  const appJs = await fs.readFile(path.join(guiRoot, 'public', 'app.mjs'), 'utf8');

  // Relative paths required for Electron mainWindow.loadFile('public/index.html')
  assert.match(html, /href="\.\/styles\.css"/);
  assert.match(html, /src="\.\/app\.mjs"/);

  // Native folder picker, reveal controls, and ! remark popovers in HTML
  assert.match(html, /id="btn-browse-scan-dir"/);
  assert.match(html, /id="btn-browse-repo-dir"/);
  assert.match(html, /id="btn-change-output-dir"/);
  assert.match(html, /id="btn-reveal-report"/);
  assert.match(html, /commandfor="popover-rebase-info"/);
  assert.match(html, /command="toggle-popover"/);
  assert.match(html, /id="popover-rebase-info"\s+popover/);

  // Desktop window drag region, fixed responsive topbar, non-overlapping flex stack, and base-select in CSS
  assert.match(css, /-webkit-app-region:\s*drag/);
  assert.match(css, /-webkit-app-region:\s*no-drag/);
  assert.match(css, /position:\s*sticky/);
  assert.match(css, /@media\s*\(max-width:\s*880px\)/);
  assert.match(css, /appearance:\s*base-select/);
  assert.match(css, /::picker\(select\)/);
  assert.match(css, /\.info-badge/);
  assert.match(css, /:is\(:popover-open,\s*\.\\:popover-open\)/);

  // Repo select dropdown shows only project name, not full path in option text
  assert.doesNotMatch(appJs, />\$\{escapeHtml\(r\.name\)\} \(\$\{escapeHtml\(r\.path\)\}\)<\/option>/);
  assert.match(appJs, /commandForElement/);

  // Pure Electron IPC in app.mjs (no HTTP fetch('/api/...'))
  assert.doesNotMatch(appJs, /fetch\(['"`]\/api\//);
  assert.match(appJs, /window\.dtk\.getState/);
  assert.match(appJs, /window\.dtk\.generateReport/);
  assert.match(appJs, /window\.dtk\.pickFolder/);
  assert.match(appJs, /window\.dtk\.pickReportOutputDir/);
  assert.match(appJs, /window\.dtk\.revealInFolder/);

  // Verify HTML entity escaping for author patterns / repo paths
  assert.equal(
    escapeHtml('Alice <alice@example.com> & "friends"'),
    'Alice &lt;alice@example.com&gt; &amp; &quot;friends&quot;'
  );
});

test('Smart Rebase UI supports favorite base branch pills and star toggle button', async () => {
  const guiRoot = path.resolve(path.dirname(new URL(import.meta.url).pathname), '..');
  const html = await fs.readFile(path.join(guiRoot, 'public', 'index.html'), 'utf8');
  const css = await fs.readFile(path.join(guiRoot, 'public', 'styles.css'), 'utf8');
  const appJs = await fs.readFile(path.join(guiRoot, 'public', 'app.mjs'), 'utf8');

  // Verify elements in index.html
  assert.match(html, /id="rebase-favorite-pills"/);
  assert.match(html, /id="btn-star-target-branch"/);
  assert.match(html, /class="rebase-input-row"/);
  assert.match(html, /class="star-icon star-icon-btn"/);
  assert.doesNotMatch(html, />⭐<\/button>/);

  // Verify styles in styles.css
  assert.match(css, /\.rebase-input-row/);
  assert.match(css, /\.custom-target-box/);
  assert.match(css, /\.favorite-pills-row/);
  assert.match(css, /\.favorite-pill/);
  assert.match(css, /\.btn-icon/);
  assert.match(css, /\.star-icon/);
  assert.match(css, /\.tab-text-compact/);

  // Verify elements in index.html
  assert.match(html, /tab-text-compact/);
  assert.match(html, /btn-text-compact/);

  // Verify functions in app.mjs
  assert.match(appJs, /renderFavoriteBranchPills/);
  assert.match(appJs, /toggleFavoriteBranch/);
  assert.match(appJs, /window\.dtk\.saveGuiSettings/);
  assert.match(appJs, /star-icon/);
  assert.doesNotMatch(appJs, /⭐/);
});

test('syncWorkspaceRepo auto-detects, auto-links, and sets isCurrentWorkspace flag', async () => {
  const configDir = await fs.mkdtemp(path.join(os.tmpdir(), 'dtk-sync-cfg-'));
  const callerDir = await fs.mkdtemp(path.join(os.tmpdir(), 'dtk-sync-call-'));
  const projectDir = path.join(callerDir, 'pos-ui');
  await initTempRepo(projectDir, 'main');
  const subfolder = path.join(projectDir, 'src', 'views');
  await fs.mkdir(subfolder, { recursive: true });

  const ipc = createIpcHandlers({
    configDir,
    callerDir,
  });

  // Initially, pos-ui is not linked
  const initial = await ipc.getState();
  assert.equal(initial.repos.length, 0);

  // Sync with subfolder of project
  const synced = await ipc.syncWorkspaceRepo({ callerDir: subfolder });
  assert.equal(synced.currentRepoName, 'pos-ui');
  assert.equal(synced.repos.length, 1);
  assert.equal(synced.repos[0].name, 'pos-ui');
  assert.equal(synced.repos[0].isCurrentWorkspace, true);

  // Subsequent getState retains the workspace repo and flag
  const refreshed = await ipc.getState();
  assert.equal(refreshed.currentRepoName, 'pos-ui');
  assert.equal(refreshed.repos[0].isCurrentWorkspace, true);
});

test('Live Inspector supports Clear button, status pills, and timestamped Smart Rebase telemetry', async () => {
  const guiRoot = path.resolve(path.dirname(new URL(import.meta.url).pathname), '..');
  const html = await fs.readFile(path.join(guiRoot, 'public', 'index.html'), 'utf8');
  const css = await fs.readFile(path.join(guiRoot, 'public', 'styles.css'), 'utf8');
  const appJs = await fs.readFile(path.join(guiRoot, 'public', 'app.mjs'), 'utf8');

  // Verify index.html contains clear button & copy output button
  assert.match(html, /id="btn-clear-output"/);
  assert.match(html, /id="btn-copy-output"[^>]*>[\s\n]*Copy Output/);

  // Verify styles.css contains telemetry status pills and actions bar
  assert.match(css, /\.pill-running/);
  assert.match(css, /\.pill-success/);
  assert.match(css, /\.pill-warning/);
  assert.match(css, /\.pill-danger/);
  assert.match(css, /\.inspector-actions/);

  // Verify app.mjs contains live rebase reset, completion banner, duration, and clear action
  assert.match(appJs, /⏳ Initiating Smart Rebase Pipeline/);
  assert.match(appJs, /SMART REBASE TELEMETRY ·/);
  assert.match(appJs, /durationMs/);
  assert.match(appJs, /toLocaleTimeString/);
  assert.match(appJs, /\$\('btn-clear-output'\)\.addEventListener\('click'/);
});





