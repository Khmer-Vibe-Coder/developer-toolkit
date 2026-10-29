#!/usr/bin/env node
import fs from 'node:fs/promises';
import path from 'node:path';
import os from 'node:os';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const defaultGuiRoot = path.resolve(__dirname, '..');

export async function stageExtensionForPackaging(guiRoot, stagingDir) {
  const rawPkg = JSON.parse(await fs.readFile(path.join(guiRoot, 'package.json'), 'utf8'));

  await fs.rm(stagingDir, { recursive: true, force: true });
  await fs.mkdir(stagingDir, { recursive: true });

  // Copy extension files
  await fs.copyFile(
    path.join(guiRoot, 'vscode-extension.cjs'),
    path.join(stagingDir, 'vscode-extension.cjs')
  );
  await fs.cp(path.join(guiRoot, 'lib'), path.join(stagingDir, 'lib'), { recursive: true });
  await fs.cp(path.join(guiRoot, 'public'), path.join(stagingDir, 'public'), { recursive: true });

  const readmePath = path.join(guiRoot, 'README.md');
  const hasReadme = await fs.stat(readmePath).then(() => true).catch(() => false);
  if (hasReadme) {
    await fs.copyFile(readmePath, path.join(stagingDir, 'README.md'));
  }

  const licensePath = path.join(guiRoot, 'LICENSE');
  const hasLicense = await fs.stat(licensePath).then(() => true).catch(() => false);
  if (hasLicense) {
    await fs.copyFile(licensePath, path.join(stagingDir, 'LICENSE'));
  }

  // Create extension-specific package.json
  const extPkg = {
    ...rawPkg,
    main: './vscode-extension.cjs',
    icon: 'public/logo.png',
    categories: ['Other', 'SCM Providers'],
    keywords: ['git', 'rebase', 'report', 'toolkit', 'smart-rebase'],
  };
  delete extPkg.devDependencies;
  delete extPkg.build;
  delete extPkg.allowScripts;

  await fs.writeFile(path.join(stagingDir, 'package.json'), `${JSON.stringify(extPkg, null, 2)}\n`, 'utf8');

  // Create .vscodeignore
  const vscodeIgnore = [
    '.git/**',
    '.github/**',
    'test/**',
    '*.test.mjs',
    'node_modules/**',
  ].join('\n');
  await fs.writeFile(path.join(stagingDir, '.vscodeignore'), `${vscodeIgnore}\n`, 'utf8');

  return {
    pkg: extPkg,
    stagingDir,
  };
}

async function main() {
  const args = process.argv.slice(2);
  const isPublish = args.includes('--publish');
  const outArgIdx = args.indexOf('--out');
  const customOut = outArgIdx !== -1 && args[outArgIdx + 1] ? args[outArgIdx + 1] : '';

  const stagingDir = await fs.mkdtemp(path.join(os.tmpdir(), 'dtk-vsix-'));
  console.log(`📦 Staging extension files at ${stagingDir}...`);
  const { pkg } = await stageExtensionForPackaging(defaultGuiRoot, stagingDir);

  const outFile = customOut
    ? path.resolve(process.cwd(), customOut)
    : path.join(defaultGuiRoot, `${pkg.name}-${pkg.version}.vsix`);

  if (isPublish) {
    console.log(`🚀 Publishing extension ${pkg.name}@${pkg.version} via vsce...`);
    const publishArgs = ['@vscode/vsce', 'publish', '--packagePath', stagingDir, ...args.filter(a => a !== '--publish')];
    const res = spawnSync('npx', publishArgs, {
      cwd: stagingDir,
      stdio: 'inherit',
      env: process.env,
    });
    if (res.status !== 0) {
      console.error(`❌ Publishing failed with exit code ${res.status}`);
      process.exit(res.status || 1);
    }
    console.log(`✅ Extension published successfully to the Visual Studio Marketplace!`);
  } else {
    console.log(`📦 Packaging VSIX bundle: ${outFile}...`);
    const packArgs = ['@vscode/vsce', 'package', '--allow-missing-repository', '--out', outFile];
    const res = spawnSync('npx', packArgs, {
      cwd: stagingDir,
      stdio: 'inherit',
      env: process.env,
    });
    if (res.status !== 0) {
      console.error(`❌ Packaging failed with exit code ${res.status}`);
      process.exit(res.status || 1);
    }
    console.log(`\n🎉 Success! VSIX package created: ${outFile}`);
    console.log(`\nTo install manually in VS Code / Antigravity IDE:`);
    console.log(`   code --install-extension "${outFile}"`);
    console.log(`   or in IDE: Extensions (⇧⌘X) -> "..." -> "Install from VSIX..."`);
  }
}

if (process.argv[1] && process.argv[1].endsWith('package-vsix.mjs')) {
  main().catch((err) => {
    console.error('Fatal error:', err);
    process.exit(1);
  });
}
