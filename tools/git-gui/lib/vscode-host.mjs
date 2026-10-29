// VS Code & Antigravity IDE Host Adapter for Developer Toolkit
export function transformHtmlForWebview(rawHtml, { cssUri, jsUri, logoUri = '', cspSource = '' } = {}) {
  const cspMeta = cspSource
    ? `<meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src ${cspSource} 'unsafe-inline'; script-src ${cspSource} 'unsafe-inline'; img-src ${cspSource} data:;">`
    : '';

  let transformed = String(rawHtml)
    .replace('<html lang="en">', '<html lang="en" class="platform-vscode">')
    .replace('<head>', `<head>\n  ${cspMeta}`)
    .replace('href="./styles.css"', `href="${cssUri}"`)
    .replace('src="./app.mjs"', `src="${jsUri}"`);

  if (logoUri) {
    transformed = transformed.replace('src="./logo.png"', `src="${logoUri}"`);
  }

  return transformed;
}

export function createVsCodeDialogAdapter(vscode) {
  return {
    async showOpenDialog(_win, opts) {
      const options = opts || _win || {};
      const dialogOpts = {
        canSelectFiles: false,
        canSelectFolders: true,
        canSelectMany: false,
        openLabel: options.title || 'Select Folder',
      };
      if (options.defaultPath && vscode?.Uri?.file) {
        dialogOpts.defaultUri = vscode.Uri.file(options.defaultPath);
      }
      const uris = await vscode.window.showOpenDialog(dialogOpts);
      if (!uris || !uris.length) {
        return { canceled: true, filePaths: [] };
      }
      return {
        canceled: false,
        filePaths: uris.map((u) => u.fsPath),
      };
    },
  };
}

export function createVsCodeShellAdapter(vscode) {
  return {
    showItemInFolder(targetPath) {
      if (vscode?.commands && vscode?.Uri?.file) {
        vscode.commands.executeCommand('revealFileInOS', vscode.Uri.file(targetPath));
      }
    },
    async openPath(targetPath) {
      if (vscode?.commands && vscode?.Uri?.file) {
        await vscode.commands.executeCommand('revealFileInOS', vscode.Uri.file(targetPath));
      }
      return '';
    },
  };
}

export async function handleWebviewMessage(msg, ipcHandlers, postMessage) {
  if (!msg || msg.type !== 'dtk:invoke' || !msg.requestId) {
    return;
  }
  const { requestId, method, payload } = msg;
  try {
    if (typeof ipcHandlers[method] !== 'function') {
      throw new Error(`Unknown IPC method: ${method}`);
    }
    const result = await ipcHandlers[method](payload || {});
    postMessage({
      type: 'dtk:response',
      requestId,
      ok: true,
      result,
    });
  } catch (err) {
    postMessage({
      type: 'dtk:response',
      requestId,
      ok: false,
      error: err?.message || String(err),
    });
  }
}
