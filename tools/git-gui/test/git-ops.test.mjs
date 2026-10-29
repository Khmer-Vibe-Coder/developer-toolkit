import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import os from 'node:os';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { inspectRepo, scanWorkspace, linkRepository, generateReport, runSmartRebase, abortSmartRebase, resolveGitRoot } from '../lib/git-ops.mjs';

const execFileAsync = promisify(execFile);

export async function initTempRepo(dir, branch = 'develop') {
  await fs.mkdir(dir, { recursive: true });
  await execFileAsync('git', ['init', '-b', branch], { cwd: dir });
  await execFileAsync('git', ['config', 'user.name', 'Test Dev'], { cwd: dir });
  await execFileAsync('git', ['config', 'user.email', 'dev@example.com'], { cwd: dir });
  await fs.writeFile(path.join(dir, 'README.md'), '# hello\n', 'utf8');
  await execFileAsync('git', ['add', '.'], { cwd: dir });
  await execFileAsync('git', ['commit', '-m', 'feat: initial commit\n\n- added readme'], { cwd: dir });
}

test('inspects repo telemetry, scans workspace, links repo, and generates multi-repo report with missing-repo/branch resilience', async () => {
  const ws = await fs.mkdtemp(path.join(os.tmpdir(), 'dtk-ws-'));
  const cfgDir = await fs.mkdtemp(path.join(os.tmpdir(), 'dtk-cfg-'));
  const repoA = path.join(ws, 'repo-alpha');
  await initTempRepo(repoA, 'develop');
  await fs.writeFile(path.join(repoA, 'untracked.txt'), 'dirty', 'utf8');

  const found = await scanWorkspace(ws, 3);
  assert.equal(found.length, 1);
  assert.equal(found[0].name, 'repo-alpha');

  const linked = await linkRepository({ target: repoA, configDir: cfgDir, callerDir: ws });
  assert.equal(linked.name, 'repo-alpha');
  assert.equal(linked.type, 'local');

  const info = await inspectRepo(linked);
  assert.equal(info.exists, true);
  assert.equal(info.currentBranch, 'develop');
  assert.equal(info.dirtyCount, 1);
  assert.ok(info.branches.includes('develop'));

  const today = new Date().toISOString().slice(0, 10);
  const report = await generateReport({
    repos: [
      linked,
      { name: 'ghost-repo', type: 'local', path: path.join(ws, 'missing'), source: path.join(ws, 'missing') },
    ],
    branchSpec: 'repo-alpha:develop,ghost-repo:develop',
    fromDate: today,
    toDate: today,
    presetLabel: `Today (${today})`,
    authorMode: 'me',
    saveToDisk: true,
    callerDir: ws,
  });

  assert.equal(report.totalCommits, 1);
  assert.match(report.markdown, /- repo-alpha\n   - feat: initial commit\n      - added readme/);
  assert.match(report.markdown, /- ghost-repo\n   - \(Repository path not found:/);
  assert.ok(report.savedFile && report.savedFile.endsWith('.md'));

  // Missing branch fallback
  const missingBranchReport = await generateReport({
    repos: [linked],
    branchSpec: 'nonexistent-branch',
    fromDate: today,
    toDate: today,
    presetLabel: `Today (${today})`,
    saveToDisk: false,
    callerDir: ws,
  });
  assert.match(missingBranchReport.markdown, /Branch 'origin\/nonexistent-branch' not found in this repository/);
});

test('runSmartRebase auto-stashes dirty files, rebases onto target branch, and restores stash', async () => {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), 'dtk-rebase-'));
  const originDir = path.join(root, 'origin.git');
  const workDir = path.join(root, 'work');

  await execFileAsync('git', ['init', '--bare', '-b', 'develop', originDir]);
  await initTempRepo(workDir, 'develop');
  await execFileAsync('git', ['remote', 'add', 'origin', originDir], { cwd: workDir });
  await execFileAsync('git', ['push', '-u', 'origin', 'develop'], { cwd: workDir });

  // Create feature branch
  await execFileAsync('git', ['checkout', '-b', 'feature/ui'], { cwd: workDir });
  await fs.writeFile(path.join(workDir, 'feature.txt'), 'feature work\n', 'utf8');
  await execFileAsync('git', ['add', 'feature.txt'], { cwd: workDir });
  await execFileAsync('git', ['commit', '-m', 'feat: add feature.txt'], { cwd: workDir });

  // Advance develop on origin via a second clone
  const peerDir = path.join(root, 'peer');
  await execFileAsync('git', ['clone', '-b', 'develop', originDir, peerDir]);
  await execFileAsync('git', ['config', 'user.name', 'Peer'], { cwd: peerDir });
  await execFileAsync('git', ['config', 'user.email', 'peer@example.com'], { cwd: peerDir });
  await fs.writeFile(path.join(peerDir, 'upstream.txt'), 'upstream change\n', 'utf8');
  await execFileAsync('git', ['add', 'upstream.txt'], { cwd: peerDir });
  await execFileAsync('git', ['commit', '-m', 'chore: upstream update'], { cwd: peerDir });
  await execFileAsync('git', ['push', 'origin', 'develop'], { cwd: peerDir });

  // Leave uncommitted untracked file in workDir before smart rebase
  await fs.writeFile(path.join(workDir, 'wip.txt'), 'uncommitted wip\n', 'utf8');

  const res = await runSmartRebase({ repoPath: workDir, targetBranch: 'develop' });
  assert.equal(res.ok, true);
  assert.equal(res.currentBranch, 'feature/ui');
  assert.equal(res.stashed, true);
  assert.equal(await fs.readFile(path.join(workDir, 'wip.txt'), 'utf8'), 'uncommitted wip\n');
  assert.equal(await fs.readFile(path.join(workDir, 'upstream.txt'), 'utf8'), 'upstream change\n');
});

test('runSmartRebase restores original branch and pops stash if target branch does not exist, and abortSmartRebase rescues conflicts', async () => {
  const repoDir = await fs.mkdtemp(path.join(os.tmpdir(), 'dtk-rebase-fail-'));
  await initTempRepo(repoDir, 'develop');
  await execFileAsync('git', ['checkout', '-b', 'feature/test'], { cwd: repoDir });
  await fs.writeFile(path.join(repoDir, 'local-wip.txt'), 'keep me safe\n', 'utf8');

  const res = await runSmartRebase({ repoPath: repoDir, targetBranch: 'nonexistent-branch' });
  assert.equal(res.ok, false);
  const restoredContent = await fs.readFile(path.join(repoDir, 'local-wip.txt'), 'utf8');
  assert.equal(restoredContent, 'keep me safe\n');

  // Now create a conflict between develop and feature/test and verify abortSmartRebase
  await fs.unlink(path.join(repoDir, 'local-wip.txt'));
  await fs.writeFile(path.join(repoDir, 'README.md'), '# feature conflicting line\n', 'utf8');
  await execFileAsync('git', ['commit', '-am', 'feat: modify readme on feature'], { cwd: repoDir });

  await execFileAsync('git', ['checkout', 'develop'], { cwd: repoDir });
  await fs.writeFile(path.join(repoDir, 'README.md'), '# develop conflicting line\n', 'utf8');
  await execFileAsync('git', ['commit', '-am', 'chore: modify readme on develop'], { cwd: repoDir });

  await execFileAsync('git', ['checkout', 'feature/test'], { cwd: repoDir });
  await fs.writeFile(path.join(repoDir, 'dirty-before-conflict.txt'), 'stash me\n', 'utf8');

  const conflictRes = await runSmartRebase({ repoPath: repoDir, targetBranch: 'develop' });
  assert.equal(conflictRes.ok, false);
  assert.equal(conflictRes.conflict, true);

  const abortRes = await abortSmartRebase({ repoPath: repoDir, originalBranch: 'feature/test' });
  assert.equal(abortRes.ok, true);
  assert.equal(await fs.readFile(path.join(repoDir, 'dirty-before-conflict.txt'), 'utf8'), 'stash me\n');
});

test('resolveGitRoot finds nearest git root for directories, nested subfolders, and files, or returns null', async () => {
  const ws = await fs.mkdtemp(path.join(os.tmpdir(), 'dtk-root-'));
  const repoDir = path.join(ws, 'my-repo');
  await initTempRepo(repoDir, 'main');

  const subDir = path.join(repoDir, 'src', 'components');
  await fs.mkdir(subDir, { recursive: true });
  const fileInSubDir = path.join(subDir, 'index.js');
  await fs.writeFile(fileInSubDir, 'console.log(1);\n', 'utf8');

  const nonGitDir = path.join(ws, 'notes');
  await fs.mkdir(nonGitDir, { recursive: true });

  const expectedRepo = (await fs.realpath(repoDir)).replace(/\\/g, '/');
  const rootFromRepo = await resolveGitRoot(repoDir);
  assert.equal(rootFromRepo, expectedRepo);

  const rootFromSubDir = await resolveGitRoot(subDir);
  assert.equal(rootFromSubDir, expectedRepo);

  const rootFromFile = await resolveGitRoot(fileInSubDir);
  assert.equal(rootFromFile, expectedRepo);

  const rootFromNonGit = await resolveGitRoot(nonGitDir);
  assert.equal(rootFromNonGit, null);
});


