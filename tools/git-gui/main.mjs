import { app, BrowserWindow, ipcMain, dialog, shell } from 'electron';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { createIpcHandlers } from './lib/ipc-controller.mjs';

const __dirname = path.dirname(fileURLToPath(import.meta.url));

let mainWindow = null;

function resolveCallerDir() {
  const args = process.argv.slice(1);
  for (let i = 0; i < args.length; i++) {
    if (args[i] === '--caller-dir' && args[i + 1]) {
      return args[i + 1];
    }
    if (args[i].startsWith('--caller-dir=')) {
      return args[i].slice('--caller-dir='.length);
    }
  }
  return process.env.DTK_CALLER_DIR || process.cwd();
}

function registerDesktopIpc() {
  const callerDir = resolveCallerDir();
  const handlers = createIpcHandlers({
    callerDir,
    dialogApi: dialog,
    shellApi: shell,
    getMainWindow: () => mainWindow,
  });

  ipcMain.handle('dtk:getState', (_event, payload) => handlers.getState(payload));
  ipcMain.handle('dtk:syncWorkspaceRepo', (_event, payload) => handlers.syncWorkspaceRepo(payload));
  ipcMain.handle('dtk:addRepo', (_event, payload) => handlers.addRepo(payload));
  ipcMain.handle('dtk:scanWorkspace', (_event, payload) => handlers.scanWorkspace(payload));
  ipcMain.handle('dtk:linkBatchRepos', (_event, payload) => handlers.linkBatchRepos(payload));
  ipcMain.handle('dtk:removeRepos', (_event, payload) => handlers.removeRepos(payload));
  ipcMain.handle('dtk:saveTemplate', (_event, payload) => handlers.saveTemplate(payload));
  ipcMain.handle('dtk:removeTemplates', (_event, payload) => handlers.removeTemplates(payload));
  ipcMain.handle('dtk:generateReport', (_event, payload) => handlers.generateReport(payload));
  ipcMain.handle('dtk:runRebase', (_event, payload) => handlers.runRebase(payload));
  ipcMain.handle('dtk:abortRebase', (_event, payload) => handlers.abortRebase(payload));
  ipcMain.handle('dtk:pickFolder', (_event, payload) => handlers.pickFolder(payload));
  ipcMain.handle('dtk:pickReportOutputDir', (_event, payload) => handlers.pickReportOutputDir(payload));
  ipcMain.handle('dtk:saveGuiSettings', (_event, payload) => handlers.saveGuiSettings(payload));
  ipcMain.handle('dtk:revealInFolder', (_event, payload) => handlers.revealInFolder(payload));
  ipcMain.handle('dtk:openPath', (_event, payload) => handlers.openPath(payload));
}

function createWindow() {
  const isMac = process.platform === 'darwin';

  mainWindow = new BrowserWindow({
    width: 1280,
    height: 820,
    minWidth: 360,
    minHeight: 480,
    title: 'Developer Toolkit',
    titleBarStyle: isMac ? 'hiddenInset' : 'default',
    trafficLightPosition: isMac ? { x: 14, y: 18 } : undefined,
    autoHideMenuBar: !isMac,
    backgroundColor: '#0f1115',
    webPreferences: {
      preload: path.join(__dirname, 'preload.cjs'),
      contextIsolation: true,
      nodeIntegration: false,
      sandbox: true,
    },
  });

  mainWindow.loadFile(path.join(__dirname, 'public', 'index.html'));

  mainWindow.on('closed', () => {
    mainWindow = null;
  });
}

app.whenReady().then(() => {
  registerDesktopIpc();
  createWindow();

  app.on('activate', () => {
    if (BrowserWindow.getAllWindows().length === 0) {
      createWindow();
    }
  });
});

app.on('window-all-closed', () => {
  if (process.platform !== 'darwin') {
    app.quit();
  }
});
