import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import os from 'node:os';
import {
  loadRepos,
  saveRepo,
  removeRepos,
  loadTemplates,
  saveTemplate,
  removeTemplates,
  loadGuiSettings,
  saveGuiSettings,
} from '../lib/config-store.mjs';

test('loads legacy 2-column repos.conf, deduplicates on save, and strips pipe characters', async () => {
  const tmpDir = await fs.mkdtemp(path.join(os.tmpdir(), 'dtk-cfg-'));
  await fs.writeFile(path.join(tmpDir, 'repos.conf'), '# comment\nlegacy-repo|/tmp/legacy\n', 'utf8');

  const initial = await loadRepos(tmpDir);
  assert.deepEqual(initial, [
    { name: 'legacy-repo', type: 'local', path: '/tmp/legacy', source: '/tmp/legacy' },
  ]);

  await saveRepo(tmpDir, { name: 'api|service', type: 'local', path: '/tmp/api', source: '/tmp/api' });
  assert.equal((await loadRepos(tmpDir))[1].name, 'apiservice');
  await saveRepo(tmpDir, { name: 'api-service', type: 'local', path: '/tmp/api', source: '/tmp/api' });

  const afterSave = await loadRepos(tmpDir);
  assert.equal(afterSave.length, 2);
  assert.equal(afterSave[1].name, 'api-service');

  const removed = await removeRepos(tmpDir, ['legacy-repo']);
  assert.equal(removed, 1);
  assert.equal((await loadRepos(tmpDir)).length, 1);
});

test('saves, updates, and removes templates in pipe-delimited format', async () => {
  const tmpDir = await fs.mkdtemp(path.join(os.tmpdir(), 'dtk-tpl-'));
  await saveTemplate(tmpDir, {
    name: 'core weekly|v1',
    repos: ['repoA', 'repoB'],
    branchSpec: 'repoA:develop,repoB:main',
    authorMode: 'custom',
    authorPattern: 'alice|bob',
    datePreset: 'this-week',
  });

  const tpls = await loadTemplates(tmpDir);
  assert.equal(tpls.length, 1);
  assert.deepEqual(tpls[0], {
    name: 'core_weeklyv1',
    repos: ['repoA', 'repoB'],
    branchSpec: 'repoA:develop,repoB:main',
    authorMode: 'custom',
    authorPattern: 'alicebob',
    datePreset: 'this-week',
  });

  const removed = await removeTemplates(tmpDir, ['core_weeklyv1']);
  assert.equal(removed, 1);
  assert.deepEqual(await loadTemplates(tmpDir), []);
});

test('loadGuiSettings defaults favoriteBranches to develop & main and persists custom favorites', async () => {
  const tmpDir = await fs.mkdtemp(path.join(os.tmpdir(), 'dtk-favs-'));
  const initial = await loadGuiSettings(tmpDir, '/tmp/project');
  assert.deepEqual(initial.favoriteBranches, ['develop', 'main']);

  const updated = await saveGuiSettings(tmpDir, {
    favoriteBranches: ['develop', 'main', 'staging', 'release/v2', ' develop '],
  });
  assert.deepEqual(updated.favoriteBranches, ['develop', 'main', 'staging', 'release/v2']);

  const reloaded = await loadGuiSettings(tmpDir, '/tmp/project');
  assert.deepEqual(reloaded.favoriteBranches, ['develop', 'main', 'staging', 'release/v2']);
});

