#!/usr/bin/env node
import fs from 'node:fs';
import fsp from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const guiRoot = path.resolve(__dirname, '..');
const electronDir = path.join(guiRoot, 'node_modules', 'electron');
const distDir = path.join(electronDir, 'dist');
const pathTxtFile = path.join(electronDir, 'path.txt');

function getPlatformExecutable() {
  const platform = process.env.npm_config_platform || os.platform();
  switch (platform) {
    case 'mas':
    case 'darwin':
      return 'Electron.app/Contents/MacOS/Electron';
    case 'freebsd':
    case 'openbsd':
    case 'linux':
      return 'electron';
    case 'win32':
      return 'electron.exe';
    default:
      throw new Error(`Electron builds are not available on platform: ${platform}`);
  }
}

function isElectronReady(platformExec) {
  if (!fs.existsSync(pathTxtFile)) return false;
  const recorded = fs.readFileSync(pathTxtFile, 'utf8').trim();
  if (recorded !== platformExec) return false;
  const binPath = path.join(distDir, platformExec);
  if (!fs.existsSync(binPath)) return false;
  if (os.platform() === 'darwin') {
    const infoPlist = path.join(distDir, 'Electron.app', 'Contents', 'Info.plist');
    if (!fs.existsSync(infoPlist)) return false;
  }
  return true;
}

async function main() {
  const platformExec = getPlatformExecutable();
  if (isElectronReady(platformExec)) {
    return;
  }

  const require = createRequire(path.join(electronDir, 'install.js'));
  const { version } = require('./package.json');
  const { downloadArtifact } = require('@electron/get');
  const checksums = require('./checksums.json');

  const platform = process.env.npm_config_platform || process.platform;
  const arch = process.env.npm_config_arch || process.arch;

  console.log(`⬇️  Preparing native Electron v${version} binary (${platform}/${arch})...`);
  const zipPath = await downloadArtifact({
    version,
    artifactName: 'electron',
    platform,
    arch,
    checksums,
  });

  await fsp.rm(distDir, { recursive: true, force: true });
  await fsp.mkdir(distDir, { recursive: true });

  if (process.platform === 'darwin') {
    execFileSync('ditto', ['-x', '-k', zipPath, distDir], { stdio: 'inherit' });
  } else if (process.platform === 'win32') {
    execFileSync('tar', ['-xf', zipPath, '-C', distDir], { stdio: 'inherit' });
  } else {
    execFileSync('unzip', ['-q', '-o', zipPath, '-d', distDir], { stdio: 'inherit' });
  }

  const srcDts = path.join(distDir, 'electron.d.ts');
  if (fs.existsSync(srcDts)) {
    await fsp.rename(srcDts, path.join(electronDir, 'electron.d.ts'));
  }

  await fsp.writeFile(pathTxtFile, platformExec, 'utf8');
  console.log(`✔ Native Electron binary ready: ${platformExec}`);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
