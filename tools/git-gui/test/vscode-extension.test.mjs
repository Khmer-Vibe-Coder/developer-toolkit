import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import {
  transformHtmlForWebview,
  handleWebviewMessage,
  createVsCodeDialogAdapter,
} from '../lib/vscode-host.mjs';
import { createDtkClientBridge } from '../public/app.mjs';
import { installExtensionToDir, uninstallExtensionFromDir } from '../scripts/install-ide-extension.mjs';
import { stageExtensionForPackaging } from '../scripts/package-vsix.mjs';

test('transformHtmlForWebview injects CSP, platform-vscode class, and Webview asset URIs', async () => {
  const guiRoot = path.resolve(path.dirname(new URL(import.meta.url).pathname), '..');
  const rawHtml = await fs.readFile(path.join(guiRoot, 'public', 'index.html'), 'utf8');

  const transformed = transformHtmlForWebview(rawHtml, {
    cssUri: 'vscode-webview://123/styles.css',
    jsUri: 'vscode-webview://123/app.mjs',
    logoUri: 'vscode-webview://123/logo.png',
    cspSource: 'vscode-webview://123',
  });

  assert.match(transformed, /class="platform-vscode"/);
  assert.match(transformed, /href="vscode-webview:\/\/123\/styles\.css"/);
  assert.match(transformed, /src="vscode-webview:\/\/123\/app\.mjs"/);
  assert.match(transformed, /src="vscode-webview:\/\/123\/logo\.png"/);
  assert.match(transformed, /Content-Security-Policy/);
});

test('handleWebviewMessage and createDtkClientBridge round-trip RPC calls over postMessage', async () => {
  const listeners = [];
  const fakeEventTarget = {
    addEventListener(type, fn) {
      if (type === 'message') listeners.push(fn);
    },
  };

  const mockHandlers = {
    async getState() {
      return {
        version: '2.0.0',
        platform: 'darwin',
        callerDir: '/tmp/workspace',
        repos: [{ name: 'inventory-api' }],
      };
    },
    async failMethod() {
      throw new Error('simulated RPC error');
    },
  };

  const fakeVsCodeApi = {
    postMessage(msg) {
      // Route message to extension host handler and send response back to webview listeners
      handleWebviewMessage(msg, mockHandlers, (reply) => {
        for (const fn of listeners) {
          fn({ data: reply });
        }
      });
    },
  };

  const client = createDtkClientBridge(fakeVsCodeApi, fakeEventTarget);
  const stateRes = await client.getState();
  assert.equal(stateRes.callerDir, '/tmp/workspace');
  assert.equal(stateRes.repos[0].name, 'inventory-api');

  await assert.rejects(() => client.failMethod(), /simulated RPC error/);
});

test('createVsCodeDialogAdapter maps vscode.window.showOpenDialog to Electron-compatible { canceled, filePaths }', async () => {
  const mockVscode = {
    Uri: {
      file(p) {
        return { fsPath: p };
      },
    },
    window: {
      async showOpenDialog() {
        return [{ fsPath: '/Users/demo/project' }];
      },
    },
  };

  const adapter = createVsCodeDialogAdapter(mockVscode);
  const picked = await adapter.showOpenDialog({ defaultPath: '/Users/demo' });
  assert.equal(picked.canceled, false);
  assert.deepEqual(picked.filePaths, ['/Users/demo/project']);
});

test('package.json, vscode-extension.cjs, and icon-activitybar.svg configure VS Code and Antigravity IDE extension', async () => {
  const guiRoot = path.resolve(path.dirname(new URL(import.meta.url).pathname), '..');
  const pkg = JSON.parse(await fs.readFile(path.join(guiRoot, 'package.json'), 'utf8'));

  assert.ok(pkg.engines?.vscode);
  assert.ok(pkg.contributes?.viewsContainers?.activitybar?.some((c) => c.id === 'dtk-workbench'));
  assert.ok(pkg.contributes?.views?.['dtk-workbench']?.some((v) => v.id === 'dtk.sidebarView'));
  assert.ok(pkg.contributes?.commands?.some((c) => c.command === 'dtk.openWorkbench'));

  const svg = await fs.readFile(path.join(guiRoot, 'public', 'icon-activitybar.svg'), 'utf8');
  assert.match(svg, /<svg/);

  const extSrc = await fs.readFile(path.join(guiRoot, 'vscode-extension.cjs'), 'utf8');
  assert.match(extSrc, /registerWebviewViewProvider\(['"]dtk\.sidebarView['"]/);
  assert.match(extSrc, /registerCommand\(['"]dtk\.openWorkbench['"]/);
  assert.match(extSrc, /panel\.iconPath/);

  // Real-time workspace folder and active editor tracking
  assert.match(extSrc, /onDidChangeWorkspaceFolders/);
  assert.match(extSrc, /onDidChangeActiveTextEditor/);
  assert.match(extSrc, /dtk:activeRepoChanged/);
});

test('vscode-extension and app.mjs handle real-time workspace repo sync and workspace pill', async () => {
  const guiRoot = path.resolve(path.dirname(new URL(import.meta.url).pathname), '..');
  const css = await fs.readFile(path.join(guiRoot, 'public', 'styles.css'), 'utf8');
  const appJs = await fs.readFile(path.join(guiRoot, 'public', 'app.mjs'), 'utf8');

  // Verify pill-workspace in styles and app.mjs
  assert.match(css, /\.pill-workspace/);
  assert.match(appJs, /pill-workspace/);
  assert.match(appJs, /dtk:activeRepoChanged/);
});


test('installExtensionToDir stages extension files, sets main to ./vscode-extension.cjs, and updates extensions.json', async () => {
  const guiRoot = path.resolve(path.dirname(new URL(import.meta.url).pathname), '..');
  const tmpExtRoot = await fs.mkdtemp(path.join(os.tmpdir(), 'dtk-ide-exts-'));

  const result = await installExtensionToDir(guiRoot, tmpExtRoot);
  assert.ok(result.targetDir.endsWith('developer-toolkit.developer-toolkit-desktop-2.0.0'));

  const stagedPkg = JSON.parse(await fs.readFile(path.join(result.targetDir, 'package.json'), 'utf8'));
  assert.equal(stagedPkg.main, './vscode-extension.cjs');

  const registry = JSON.parse(await fs.readFile(path.join(tmpExtRoot, 'extensions.json'), 'utf8'));
  assert.equal(registry.length, 1);
  assert.equal(registry[0].identifier.id, 'developer-toolkit.developer-toolkit-desktop');
});

test('stageExtensionForPackaging sanitizes manifest, sets vscode main, icon, and .vscodeignore', async () => {
  const guiRoot = path.resolve(path.dirname(new URL(import.meta.url).pathname), '..');
  const tmpStaging = await fs.mkdtemp(path.join(os.tmpdir(), 'dtk-vsix-staging-'));

  const result = await stageExtensionForPackaging(guiRoot, tmpStaging);
  assert.equal(result.pkg.main, './vscode-extension.cjs');
  assert.equal(result.pkg.icon, 'public/logo.png');
  assert.ok(result.pkg.categories?.includes('SCM Providers'));
  assert.ok(result.pkg.keywords?.includes('smart-rebase'));
  assert.equal(result.pkg.devDependencies, undefined);
  assert.equal(result.pkg.build, undefined);

  // Files staged
  const files = await fs.readdir(tmpStaging);
  assert.ok(files.includes('vscode-extension.cjs'));
  assert.ok(files.includes('package.json'));
  assert.ok(files.includes('.vscodeignore'));
  assert.ok(files.includes('public'));
  assert.ok(files.includes('lib'));
});

test('uninstallExtensionFromDir removes extension folder and cleans extensions.json registry', async () => {
  const guiRoot = path.resolve(path.dirname(new URL(import.meta.url).pathname), '..');
  const tmpExtRoot = await fs.mkdtemp(path.join(os.tmpdir(), 'dtk-ide-uninst-'));

  const installed = await installExtensionToDir(guiRoot, tmpExtRoot);
  assert.equal((await fs.readdir(tmpExtRoot)).some((f) => f.startsWith(installed.extId)), true);

  await uninstallExtensionFromDir(installed.extId, tmpExtRoot);
  assert.equal((await fs.readdir(tmpExtRoot)).some((f) => f.startsWith(installed.extId)), false);

  const registry = JSON.parse(await fs.readFile(path.join(tmpExtRoot, 'extensions.json'), 'utf8'));
  assert.equal(registry.length, 0);
});




