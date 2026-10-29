const vscode = require('vscode');
const fs = require('node:fs/promises');
const path = require('node:path');
const os = require('node:os');

function getActiveWorkspaceDir() {
  const activeDoc = vscode.window.activeTextEditor?.document;
  if (activeDoc && activeDoc.uri?.scheme === 'file' && activeDoc.uri.fsPath) {
    return path.dirname(activeDoc.uri.fsPath);
  }
  const folders = vscode.workspace.workspaceFolders;
  if (folders && folders.length > 0 && folders[0].uri?.fsPath) {
    return folders[0].uri.fsPath;
  }
  return os.homedir();
}

const activeWebviews = new Set();

async function setupWebview(webview, extensionUri) {
  const [{ createIpcHandlers }, { transformHtmlForWebview, createVsCodeDialogAdapter, createVsCodeShellAdapter, handleWebviewMessage }] =
    await Promise.all([import('./lib/ipc-controller.mjs'), import('./lib/vscode-host.mjs')]);

  activeWebviews.add(webview);

  const publicDir = vscode.Uri.joinPath(extensionUri, 'public');
  webview.options = {
    enableScripts: true,
    localResourceRoots: [publicDir],
  };

  const cssUri = webview.asWebviewUri(vscode.Uri.joinPath(publicDir, 'styles.css')).toString();
  const jsUri = webview.asWebviewUri(vscode.Uri.joinPath(publicDir, 'app.mjs')).toString();
  const logoUri = webview.asWebviewUri(vscode.Uri.joinPath(publicDir, 'logo.png')).toString();

  const htmlPath = path.join(extensionUri.fsPath, 'public', 'index.html');
  const rawHtml = await fs.readFile(htmlPath, 'utf8');

  try {
    webview.html = transformHtmlForWebview(rawHtml, {
      cssUri,
      jsUri,
      logoUri,
      cspSource: webview.cspSource,
    });
  } catch {
    activeWebviews.delete(webview);
    return;
  }

  const handlers = createIpcHandlers({
    callerDir: getActiveWorkspaceDir(),
    dialogApi: createVsCodeDialogAdapter(vscode),
    shellApi: createVsCodeShellAdapter(vscode),
  });

  webview.onDidReceiveMessage((msg) => {
    handleWebviewMessage(msg, handlers, (reply) => {
      try {
        webview.postMessage(reply);
      } catch {
        activeWebviews.delete(webview);
      }
    });
  });
}

function activate(context) {
  let activePanel = null;

  let syncTimer = null;
  const notifyActiveWorkspace = () => {
    if (syncTimer) clearTimeout(syncTimer);
    syncTimer = setTimeout(async () => {
      const activeDir = getActiveWorkspaceDir();
      for (const webview of Array.from(activeWebviews)) {
        try {
          webview.postMessage({
            type: 'dtk:activeRepoChanged',
            callerDir: activeDir,
          });
        } catch {
          activeWebviews.delete(webview);
        }
      }
    }, 150);
  };

  context.subscriptions.push(
    vscode.workspace.onDidChangeWorkspaceFolders(notifyActiveWorkspace),
    vscode.window.onDidChangeActiveTextEditor(notifyActiveWorkspace)
  );

  const sidebarProvider = {
    async resolveWebviewView(webviewView) {
      const webview = webviewView.webview;
      webviewView.onDidDispose?.(() => {
        activeWebviews.delete(webview);
      });
      await setupWebview(webview, context.extensionUri);
    },
  };

  context.subscriptions.push(
    vscode.window.registerWebviewViewProvider('dtk.sidebarView', sidebarProvider, {
      webviewOptions: { retainContextWhenHidden: true },
    })
  );

  context.subscriptions.push(
    vscode.commands.registerCommand('dtk.openWorkbench', async () => {
      if (activePanel) {
        try {
          activePanel.reveal(vscode.ViewColumn.One);
          return;
        } catch {
          activePanel = null;
        }
      }

      const panel = vscode.window.createWebviewPanel(
        'dtk.workbenchPanel',
        'Developer Toolkit (dtk)',
        vscode.ViewColumn.One,
        {
          enableScripts: true,
          retainContextWhenHidden: true,
          localResourceRoots: [vscode.Uri.joinPath(context.extensionUri, 'public')],
        }
      );
      panel.iconPath = vscode.Uri.joinPath(context.extensionUri, 'public', 'logo.png');
      activePanel = panel;
      const webview = panel.webview;

      panel.onDidDispose(() => {
        activeWebviews.delete(webview);
        if (activePanel === panel) {
          activePanel = null;
        }
      });

      await setupWebview(webview, context.extensionUri);
    })
  );
}

function deactivate() {}

module.exports = {
  activate,
  deactivate,
};
