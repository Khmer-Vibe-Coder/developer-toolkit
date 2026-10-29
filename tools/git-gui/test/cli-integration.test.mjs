import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const execFileAsync = promisify(execFile);
const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../../..');

test('git-gui.sh --help, --version, and git-toolkit.sh --help advertise GUI command and handle Electron binary install', async () => {
  const { stdout: guiHelp } = await execFileAsync('bash', [
    path.join(ROOT, 'tools/git-gui/git-gui.sh'),
    '--help',
  ]);
  assert.match(guiHelp, /Developer Toolkit GUI/);

  const { stdout: guiVer } = await execFileAsync('bash', [
    path.join(ROOT, 'tools/git-gui/git-gui.sh'),
    '--version',
  ]);
  assert.match(guiVer, /git-gui \(Developer Toolkit\)/);

  const { stdout: dtkHelp } = await execFileAsync('bash', [
    path.join(ROOT, 'tools/git-toolkit/git-toolkit.sh'),
    '--help',
  ]);
  assert.match(dtkHelp, /dtk gui/);
  assert.match(dtkHelp, /dtk install-ext/);
  assert.match(guiHelp, /Electron Desktop App|Desktop App/i);

  const guiScript = await fs.readFile(path.join(ROOT, 'tools/git-gui/git-gui.sh'), 'utf8');
  assert.match(guiScript, /node_modules\/electron\/path\.txt/);
  assert.match(guiScript, /scripts\/ensure-electron\.mjs/);
});
