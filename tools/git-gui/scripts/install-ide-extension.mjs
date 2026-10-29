#!/usr/bin/env node
import fs from 'node:fs/promises';
import path from 'node:path';
import os from 'node:os';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const defaultGuiRoot = path.resolve(__dirname, '..');

export async function installExtensionToDir(guiRoot, extensionsRoot) {
  const rawPkg = JSON.parse(await fs.readFile(path.join(guiRoot, 'package.json'), 'utf8'));
  const publisher = rawPkg.publisher || 'developer-toolkit';
  const extName = rawPkg.name || 'developer-toolkit-desktop';
  const version = rawPkg.version || '2.0.0';
  const extId = `${publisher}.${extName}`;
  const folderName = `${extId}-${version}`;
  const targetDir = path.join(extensionsRoot, folderName);

  await fs.mkdir(extensionsRoot, { recursive: true });
  await fs.rm(targetDir, { recursive: true, force: true });
  await fs.mkdir(targetDir, { recursive: true });

  // Copy vscode-extension.cjs, lib/, and public/
  await fs.copyFile(
    path.join(guiRoot, 'vscode-extension.cjs'),
    path.join(targetDir, 'vscode-extension.cjs')
  );
  await fs.cp(path.join(guiRoot, 'lib'), path.join(targetDir, 'lib'), { recursive: true });
  await fs.cp(path.join(guiRoot, 'public'), path.join(targetDir, 'public'), { recursive: true });

  // Write extension package.json with main pointing to ./vscode-extension.cjs
  const extPkg = {
    ...rawPkg,
    main: './vscode-extension.cjs',
  };
  delete extPkg.devDependencies;
  delete extPkg.build;
  delete extPkg.allowScripts;

  await fs.writeFile(path.join(targetDir, 'package.json'), `${JSON.stringify(extPkg, null, 2)}\n`, 'utf8');

  // Update extensions.json registry index used by Antigravity IDE and VS Code
  const registryPath = path.join(extensionsRoot, 'extensions.json');
  let registry = [];
  try {
    const rawReg = await fs.readFile(registryPath, 'utf8');
    const parsed = JSON.parse(rawReg);
    if (Array.isArray(parsed)) {
      registry = parsed.filter((item) => item?.identifier?.id !== extId);
    }
  } catch {
    registry = [];
  }

  const normalizedTarget = targetDir.replace(/\\/g, '/');
  registry.push({
    identifier: {
      id: extId,
    },
    version,
    location: {
      $mid: 1,
      fsPath: targetDir,
      external: `file://${normalizedTarget.startsWith('/') ? '' : '/'}${normalizedTarget}`,
      path: normalizedTarget,
      scheme: 'file',
    },
    relativeLocation: folderName,
    metadata: {
      installedTimestamp: Date.now(),
      pinned: false,
      source: 'vsix',
    },
  });

  await fs.writeFile(registryPath, JSON.stringify(registry), 'utf8');

  return {
    extId,
    version,
    targetDir,
    registryPath,
  };
}

export async function uninstallExtensionFromDir(extId, extensionsRoot) {
  const entries = await fs.readdir(extensionsRoot, { withFileTypes: true }).catch(() => []);
  for (const entry of entries) {
    if (entry.isDirectory() && entry.name.startsWith(extId)) {
      await fs.rm(path.join(extensionsRoot, entry.name), { recursive: true, force: true });
    }
  }

  const registryPath = path.join(extensionsRoot, 'extensions.json');
  try {
    const rawReg = await fs.readFile(registryPath, 'utf8');
    const parsed = JSON.parse(rawReg);
    if (Array.isArray(parsed)) {
      const updated = parsed.filter((item) => item?.identifier?.id !== extId);
      await fs.writeFile(registryPath, JSON.stringify(updated), 'utf8');
    }
  } catch {}
}

async function runCli() {
  const isUninstall = process.argv.includes('--uninstall');
  const home = os.homedir();
  const extId = 'developer-toolkit.developer-toolkit-desktop';
  const targets = [
    { label: 'Antigravity IDE', dir: path.join(home, '.antigravity-ide', 'extensions') },
    { label: 'Antigravity', dir: path.join(home, '.antigravity', 'extensions') },
    { label: 'VS Code', dir: path.join(home, '.vscode', 'extensions') },
  ];

  if (isUninstall) {
    console.log('======================================================');
    console.log('🗑️  Uninstalling Developer Toolkit Extension from IDEs');
    console.log('======================================================');
    for (const t of targets) {
      await uninstallExtensionFromDir(extId, t.dir);
      console.log(`✔ Removed from ${t.label}: ${t.dir}`);
    }
    console.log('\n✅ Uninstalled! In Antigravity IDE or VS Code:');
    console.log('   Press ⌘⇧P (or Ctrl+Shift+P) -> "Developer: Reload Window"');
    return;
  }

  console.log('======================================================');
  console.log('🧩 Installing Developer Toolkit Extension for IDEs');
  console.log('======================================================');

  for (const t of targets) {
    const res = await installExtensionToDir(defaultGuiRoot, t.dir);
    console.log(`✔ Installed for ${t.label}: ${res.targetDir}`);
  }

  console.log('\n✅ Done! In Antigravity IDE or VS Code:');
  console.log('   1. Press ⌘⇧P (or Ctrl+Shift+P) -> "Developer: Reload Window"');
  console.log('   2. Click the "dtk" icon in the Activity Bar (left sidebar)');
  console.log('      or run "Developer Toolkit: Open Workbench in Editor Tab"!');
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  runCli().catch((err) => {
    console.error(err);
    process.exit(1);
  });
}
