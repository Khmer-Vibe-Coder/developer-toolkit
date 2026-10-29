import fs from 'node:fs/promises';
import path from 'node:path';
import os from 'node:os';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { saveRepo, getDefaultConfigDir } from './config-store.mjs';

const execFileAsync = promisify(execFile);

export async function runGit(args, cwd) {
  try {
    const { stdout, stderr } = await execFileAsync('git', args, {
      cwd,
      maxBuffer: 16 * 1024 * 1024,
    });
    return { ok: true, stdout: stdout.trimEnd(), stderr: stderr.trimEnd() };
  } catch (err) {
    return {
      ok: false,
      stdout: (err.stdout || '').trimEnd(),
      stderr: (err.stderr || err.message || '').trimEnd(),
      code: err.code,
    };
  }
}

export async function resolveGitRoot(startDir) {
  if (!startDir) return null;
  let targetPath = path.resolve(String(startDir).trim());
  try {
    const stat = await fs.stat(targetPath);
    if (!stat.isDirectory()) {
      targetPath = path.dirname(targetPath);
    }
  } catch {
    return null;
  }

  const res = await runGit(['rev-parse', '--show-toplevel'], targetPath);
  if (res.ok && res.stdout) {
    let rootPath = res.stdout.trim().replace(/\\/g, '/');
    try {
      rootPath = (await fs.realpath(rootPath)).replace(/\\/g, '/');
    } catch {}
    return rootPath;
  }
  return null;
}

export function normalizeInputPath(rawPath, callerDir = process.cwd()) {
  let p = String(rawPath || '').trim();
  if (!p) return callerDir;
  if (p.startsWith('~')) {
    p = path.join(os.homedir(), p.slice(1));
  }
  p = p.replace(/\\/g, '/');
  if (!path.isAbsolute(p) && !/^[A-Za-z]:\//.test(p)) {
    p = path.resolve(callerDir, p);
  }
  return p;
}

export function isRemoteUrl(target, callerDir = process.cwd()) {
  const t = String(target || '').trim();
  if (/^(https?|ssh|git|file):\/\//.test(t) || /^git@/.test(t)) {
    return true;
  }
  if (t.endsWith('.git')) {
    return true;
  }
  return false;
}

export function extractRepoNameFromUrl(url) {
  let clean = String(url || '').replace(/\/+$/, '');
  const slashIdx = clean.lastIndexOf('/');
  if (slashIdx >= 0) clean = clean.slice(slashIdx + 1);
  const colonIdx = clean.lastIndexOf(':');
  if (colonIdx >= 0) clean = clean.slice(colonIdx + 1);
  if (clean.endsWith('.git')) clean = clean.slice(0, -4);
  return clean;
}

export async function getRepoBranches(repoPath, fetchRemote = false) {
  const currRes = await runGit(['rev-parse', '--abbrev-ref', 'HEAD'], repoPath);
  const currBranch = currRes.ok ? currRes.stdout.trim() : '';

  let refScope = 'refs/heads';
  const originRes = await runGit(['remote', 'get-url', 'origin'], repoPath);
  if (originRes.ok) {
    if (fetchRemote) {
      await runGit(['fetch', 'origin', '--prune', '--quiet'], repoPath);
    }
    const remoteCheck = await runGit(['for-each-ref', '--count=1', 'refs/remotes/origin'], repoPath);
    if (remoteCheck.ok && remoteCheck.stdout.trim()) {
      refScope = 'refs/remotes/origin';
    }
  }

  const refsRes = await runGit(['for-each-ref', '--format=%(refname:short)', refScope], repoPath);
  const rawBranches = [];
  if (refsRes.ok && refsRes.stdout) {
    for (const line of refsRes.stdout.split(/\r?\n/)) {
      let b = line.trim();
      if (!b) continue;
      if (b.startsWith('origin/')) b = b.slice('origin/'.length);
      if (b === 'HEAD' || b === 'origin') continue;
      rawBranches.push(b);
    }
  }

  // Also include local branches if refScope was origin so local-only branches remain selectable
  if (refScope === 'refs/remotes/origin') {
    const localRefs = await runGit(['for-each-ref', '--format=%(refname:short)', 'refs/heads'], repoPath);
    if (localRefs.ok && localRefs.stdout) {
      for (const line of localRefs.stdout.split(/\r?\n/)) {
        const b = line.trim();
        if (b && b !== 'HEAD' && !rawBranches.includes(b)) {
          rawBranches.push(b);
        }
      }
    }
  }

  const ordered = [];
  const priority = [currBranch, 'develop', 'main', 'master', 'staging'];
  for (const p of priority) {
    if (!p || p === 'HEAD') continue;
    if (rawBranches.includes(p) && !ordered.includes(p)) {
      ordered.push(p);
    }
  }
  for (const b of rawBranches) {
    if (!ordered.includes(b)) {
      ordered.push(b);
    }
  }
  return { currentBranch: currBranch, branches: ordered };
}

export async function inspectRepo(entry) {
  const base = {
    name: entry.name,
    type: entry.type || 'local',
    path: entry.path,
    source: entry.source || entry.path,
    exists: false,
    currentBranch: '',
    dirtyCount: 0,
    rebasing: false,
    branches: [],
  };

  try {
    const stat = await fs.stat(entry.path);
    if (!stat.isDirectory()) return base;
  } catch {
    return base;
  }

  const gitDirRes = await runGit(['rev-parse', '--git-dir'], entry.path);
  if (!gitDirRes.ok) return base;

  base.exists = true;
  const { currentBranch, branches } = await getRepoBranches(entry.path, false);
  base.currentBranch = currentBranch;
  base.branches = branches;

  if (base.type === 'local') {
    const statusRes = await runGit(['status', '--porcelain'], entry.path);
    if (statusRes.ok && statusRes.stdout.trim()) {
      base.dirtyCount = statusRes.stdout.trim().split(/\r?\n/).filter(Boolean).length;
    }
    const gitDir = path.resolve(entry.path, gitDirRes.stdout.trim());
    const rebaseMerge = await fs.stat(path.join(gitDir, 'rebase-merge')).catch(() => null);
    const rebaseApply = await fs.stat(path.join(gitDir, 'rebase-apply')).catch(() => null);
    base.rebasing = Boolean(rebaseMerge || rebaseApply);
  }

  return base;
}

export async function scanWorkspace(scanDir, maxDepth = 4, callerDir = process.cwd()) {
  const resolvedDir = normalizeInputPath(scanDir, callerDir);
  const stat = await fs.stat(resolvedDir).catch(() => null);
  if (!stat || !stat.isDirectory()) {
    throw new Error(`Directory not found: ${resolvedDir}`);
  }

  const results = [];

  async function walk(curr, depth) {
    if (depth > maxDepth) return;
    let entries;
    try {
      entries = await fs.readdir(curr, { withFileTypes: true });
    } catch {
      return;
    }

    const hasGit = entries.some((e) => e.name === '.git');
    if (hasGit) {
      const normalized = curr.replace(/\\/g, '/');
      results.push({
        name: path.basename(normalized),
        path: normalized,
      });
    }

    for (const entry of entries) {
      if (!entry.isDirectory()) continue;
      if (entry.name === '.git' || entry.name === 'node_modules' || entry.name.startsWith('.')) {
        continue;
      }
      await walk(path.join(curr, entry.name), depth + 1);
    }
  }

  await walk(resolvedDir, 1);
  results.sort((a, b) => a.path.localeCompare(b.path));
  return results;
}

export async function linkRepository({
  target,
  customName = '',
  configDir = getDefaultConfigDir(),
  callerDir = process.cwd(),
}) {
  const rawTarget = String(target || callerDir).trim();
  const localCandidate = normalizeInputPath(rawTarget, callerDir);
  const localStat = await fs.stat(localCandidate).catch(() => null);

  if (!localStat && isRemoteUrl(rawTarget, callerDir)) {
    const repoName = (customName || extractRepoNameFromUrl(rawTarget)).trim();
    if (!repoName) {
      throw new Error('Could not determine repository name from URL. Provide a custom alias.');
    }
    const remotesDir = path.join(configDir, 'remotes');
    await fs.mkdir(remotesDir, { recursive: true });
    const cacheDir = path.join(remotesDir, `${repoName}.git`);

    const cacheStat = await fs.stat(cacheDir).catch(() => null);
    if (cacheStat && cacheStat.isDirectory()) {
      await runGit(['remote', 'set-url', 'origin', rawTarget], cacheDir);
      await runGit(['config', 'remote.origin.fetch', '+refs/heads/*:refs/heads/*'], cacheDir);
      await runGit(['fetch', 'origin', '--prune', '--filter=blob:none', '--quiet'], cacheDir);
    } else {
      const cloneRes = await runGit(
        ['clone', '--bare', '--filter=blob:none', rawTarget, cacheDir, '--quiet'],
        remotesDir
      );
      if (!cloneRes.ok) {
        throw new Error(`Failed to link remote repository: ${cloneRes.stderr || rawTarget}`);
      }
      await runGit(['config', 'remote.origin.fetch', '+refs/heads/*:refs/heads/*'], cacheDir);
      await runGit(['fetch', 'origin', '--prune', '--filter=blob:none', '--quiet'], cacheDir);
    }

    const entry = { name: repoName, type: 'remote', path: cacheDir, source: rawTarget };
    await saveRepo(configDir, entry);
    return entry;
  }

  if (!localStat || !localStat.isDirectory()) {
    throw new Error(`Directory not found: ${localCandidate}`);
  }

  let repoRoot = '';
  const topRes = await runGit(['rev-parse', '--show-toplevel'], localCandidate);
  if (topRes.ok && topRes.stdout.trim()) {
    repoRoot = topRes.stdout.trim();
  } else {
    const bareRes = await runGit(['rev-parse', '--is-bare-repository'], localCandidate);
    if (bareRes.ok && bareRes.stdout.trim() === 'true') {
      repoRoot = localCandidate;
    } else {
      throw new Error(`'${localCandidate}' is not a valid Git repository.`);
    }
  }

  repoRoot = repoRoot.replace(/\\/g, '/');
  const repoName = (customName || path.basename(repoRoot)).trim();
  const entry = { name: repoName, type: 'local', path: repoRoot, source: repoRoot };
  await saveRepo(configDir, entry);
  return entry;
}

async function resolveRepoBranchRef(repoPath, requestedBranch) {
  let branch = requestedBranch || 'develop';
  if (branch === 'CURRENT' || branch === 'HEAD') {
    const headRes = await runGit(['rev-parse', '--abbrev-ref', 'HEAD'], repoPath);
    branch = headRes.ok && headRes.stdout.trim() ? headRes.stdout.trim() : 'HEAD';
  }

  const remoteRef = `refs/remotes/origin/${branch}`;
  const hasRemote = await runGit(['show-ref', '--verify', '--quiet', remoteRef], repoPath);
  if (hasRemote.ok) return remoteRef;

  const localRef = `refs/heads/${branch}`;
  const hasLocal = await runGit(['show-ref', '--verify', '--quiet', localRef], repoPath);
  if (hasLocal.ok) return localRef;

  if (branch === 'HEAD') {
    const hasHead = await runGit(['rev-parse', '--verify', 'HEAD'], repoPath);
    if (hasHead.ok) return 'HEAD';
  }

  return null;
}

function parseBranchForRepo(branchSpec, repoName) {
  if (!branchSpec) return 'develop';
  if (typeof branchSpec === 'object' && branchSpec !== null) {
    return branchSpec[repoName] || branchSpec.default || 'develop';
  }
  const specStr = String(branchSpec).trim();
  if (specStr.includes(':')) {
    for (const pair of specStr.split(',')) {
      const [rName, rBranch] = pair.split(':').map((s) => s.trim());
      if (rName === repoName && rBranch) {
        return rBranch;
      }
    }
    return 'develop';
  }
  return specStr;
}

function formatReportTimestamp(now = new Date()) {
  const pad = (n) => String(n).padStart(2, '0');
  return (
    `${now.getFullYear()}${pad(now.getMonth() + 1)}${pad(now.getDate())}-` +
    `${pad(now.getHours())}${pad(now.getMinutes())}${pad(now.getSeconds())}`
  );
}

export async function generateReport({
  repos = [],
  branchSpec = 'develop',
  fromDate,
  toDate,
  presetLabel = '',
  authorMode = 'all',
  authorPattern = '',
  doFetch = false,
  includeMerges = false,
  detailed = false,
  saveToDisk = true,
  outputExt = 'md',
  customOutput = '',
  outputDir = '',
  callerDir = process.cwd(),
}) {
  if (!repos.length) {
    throw new Error('No repositories selected');
  }

  const lines = [];
  let totalCommits = 0;
  const perRepoCounts = {};

  for (const repo of repos) {
    const rName = repo.name;
    const rType = repo.type || 'local';
    const rPath = repo.path;
    let repoBranch = parseBranchForRepo(branchSpec, rName);

    lines.push(`- ${rName}`);
    perRepoCounts[rName] = 0;

    const stat = await fs.stat(rPath).catch(() => null);
    const gitValid = stat && stat.isDirectory() && (await runGit(['rev-parse', '--git-dir'], rPath)).ok;
    if (!gitValid) {
      lines.push(`   - (Repository path not found: ${rPath})`);
      continue;
    }

    if (repoBranch === 'CURRENT' || repoBranch === 'HEAD') {
      const currRes = await runGit(['rev-parse', '--abbrev-ref', 'HEAD'], rPath);
      repoBranch = currRes.ok && currRes.stdout.trim() ? currRes.stdout.trim() : 'HEAD';
    }

    // Fetch latest remote branch without checking out or altering working files
    if (doFetch || rType === 'remote') {
      const hasOrigin = await runGit(['remote', 'get-url', 'origin'], rPath);
      if (hasOrigin.ok) {
        if (rType === 'remote') {
          await runGit(
            ['fetch', 'origin', `+refs/heads/${repoBranch}:refs/heads/${repoBranch}`, '--filter=blob:none', '--quiet'],
            rPath
          );
        } else {
          await runGit(
            ['fetch', 'origin', `${repoBranch}:refs/remotes/origin/${repoBranch}`, '--quiet'],
            rPath
          );
        }
      }
    }

    const resolvedRef = await resolveRepoBranchRef(rPath, repoBranch);
    if (!resolvedRef) {
      lines.push(`   - (Branch 'origin/${repoBranch}' not found in this repository)`);
      continue;
    }

    const logArgs = [
      'log',
      resolvedRef,
      `--since=${fromDate} 00:00:00`,
      `--until=${toDate} 23:59:59`,
    ];

    if (!includeMerges) {
      logArgs.push('--no-merges');
    }

    if (authorMode === 'me') {
      const emailRes = await runGit(['config', 'user.email'], rPath);
      const nameRes = await runGit(['config', 'user.name'], rPath);
      const authorVal = (emailRes.ok && emailRes.stdout.trim()) || (nameRes.ok && nameRes.stdout.trim()) || '';
      if (authorVal) {
        logArgs.push(`--author=${authorVal}`);
      }
    } else if (authorMode === 'custom' && authorPattern) {
      logArgs.push(`--author=${authorPattern}`);
    }

    if (detailed) {
      logArgs.push('--date=short', '--pretty=format:@@COMMIT_START@@[%h] %s (%ad - %an)%n%b');
    } else {
      logArgs.push('--pretty=format:@@COMMIT_START@@%s%n%b');
    }

    const logRes = await runGit(logArgs, rPath);
    const commitsOutput = logRes.ok ? logRes.stdout.trim() : '';

    if (!commitsOutput) {
      lines.push('   - (No commits in this period)');
    } else {
      for (const rawLine of commitsOutput.split(/\r?\n/)) {
        if (rawLine.startsWith('@@COMMIT_START@@')) {
          const subjectText = rawLine.slice('@@COMMIT_START@@'.length).trim();
          if (!subjectText) continue;
          lines.push(`   - ${subjectText}`);
          totalCommits += 1;
          perRepoCounts[rName] += 1;
        } else {
          let trimmedBody = rawLine.trim();
          if (!trimmedBody) continue;
          if (trimmedBody.startsWith('- ') || trimmedBody.startsWith('* ')) {
            trimmedBody = trimmedBody.slice(2).trim();
          }
          lines.push(`      - ${trimmedBody}`);
        }
      }
    }
  }

  const markdown = `${lines.join('\n')}\n`;
  let savedFile = null;

  if (saveToDisk) {
    const reportDir = outputDir || path.join(callerDir, 'report');
    await fs.mkdir(reportDir, { recursive: true });
    const ext = outputExt === 'txt' ? 'txt' : 'md';
    if (customOutput) {
      savedFile = customOutput.includes('/') || customOutput.includes('\\')
        ? path.resolve(callerDir, customOutput)
        : path.join(reportDir, customOutput);
    } else {
      savedFile = path.join(reportDir, `commit-report-${formatReportTimestamp()}.${ext}`);
    }
    await fs.mkdir(path.dirname(savedFile), { recursive: true });
    await fs.writeFile(savedFile, markdown, 'utf8');
  }

  return {
    markdown,
    totalCommits,
    repoCount: repos.length,
    savedFile,
    presetLabel,
    fromDate,
    toDate,
    perRepoCounts,
  };
}

export async function runSmartRebase({ repoPath, targetBranch = 'develop' }) {
  const steps = [];
  const checkTree = await runGit(['rev-parse', '--is-inside-work-tree'], repoPath);
  if (!checkTree.ok) {
    return {
      ok: false,
      currentBranch: '',
      targetBranch,
      stashed: false,
      steps: [{ step: 'Verify Git repository', status: 'error', detail: 'Not inside a valid Git repository.' }],
      error: 'Not inside a valid Git repository.',
    };
  }

  const currRes = await runGit(['rev-parse', '--abbrev-ref', 'HEAD'], repoPath);
  const currentBranch = currRes.ok ? currRes.stdout.trim() : 'HEAD';
  const target = (targetBranch || 'develop').trim();
  const hasOrigin = (await runGit(['remote', 'get-url', 'origin'], repoPath)).ok;

  if (currentBranch === target) {
    steps.push({
      step: 'Check working branch',
      status: 'done',
      detail: `Already on '${target}'. Pulling latest updates directly.`,
    });
    if (hasOrigin) {
      const pullRes = await runGit(['pull', 'origin', target], repoPath);
      if (!pullRes.ok) {
        steps.push({ step: `Pull origin/${target}`, status: 'error', detail: pullRes.stderr || 'Pull failed' });
        return { ok: false, currentBranch, targetBranch: target, stashed: false, steps, error: pullRes.stderr };
      }
      steps.push({ step: `Pull origin/${target}`, status: 'done', detail: `'${target}' is up to date.` });
    }
    return { ok: true, currentBranch, targetBranch: target, stashed: false, steps };
  }

  // Step 1: Check for pending changes and auto-stash
  let stashed = false;
  const statusRes = await runGit(['status', '--porcelain'], repoPath);
  const hasPending = Boolean(statusRes.ok && statusRes.stdout.trim());

  if (hasPending) {
    await runGit(['add', '-A'], repoPath);
    const stashToken = `auto-rebase-stash [${currentBranch}] at ${new Date().toISOString()}`;
    const stashRes = await runGit(['stash', 'push', '-u', '-m', stashToken], repoPath);
    if (!stashRes.ok) {
      steps.push({ step: 'Auto-stash pending changes', status: 'error', detail: stashRes.stderr });
      return { ok: false, currentBranch, targetBranch: target, stashed: false, steps, error: stashRes.stderr };
    }
    stashed = true;
    steps.push({
      step: 'Auto-stash pending changes',
      status: 'done',
      detail: `Stashed modified & untracked files (${stashToken}).`,
    });
  } else {
    steps.push({
      step: 'Check working directory',
      status: 'skipped',
      detail: 'Working directory is clean. No stash needed.',
    });
  }

  // Step 2: Checkout target branch & pull from origin (if remote origin exists)
  if (hasOrigin) {
    const hasLocalTarget = await runGit(['show-ref', '--verify', '--quiet', `refs/heads/${target}`], repoPath);
    if (!hasLocalTarget.ok) {
      await runGit(['fetch', 'origin', target], repoPath);
    }
  }
  const checkoutTargetRes = await runGit(['checkout', target], repoPath);
  if (!checkoutTargetRes.ok) {
    steps.push({
      step: `Switch to '${target}'`,
      status: 'error',
      detail: checkoutTargetRes.stderr || `Failed to checkout '${target}'.`,
    });
    if (stashed) {
      await runGit(['stash', 'pop'], repoPath);
      steps.push({
        step: 'Rollback & restore stash',
        status: 'done',
        detail: `Restored stashed changes on '${currentBranch}'.`,
      });
    }
    return {
      ok: false,
      currentBranch,
      targetBranch: target,
      stashed: false,
      steps,
      error: checkoutTargetRes.stderr || `Failed to checkout '${target}'.`,
    };
  }
  steps.push({ step: `Switch to '${target}'`, status: 'done', detail: `Checked out '${target}'.` });

  if (hasOrigin) {
    const pullRes = await runGit(['pull', 'origin', target], repoPath);
    if (!pullRes.ok) {
      steps.push({
        step: `Pull latest from origin/${target}`,
        status: 'error',
        detail: pullRes.stderr || `Failed to pull origin/${target}.`,
      });
      await runGit(['checkout', currentBranch], repoPath);
      if (stashed) {
        await runGit(['stash', 'pop'], repoPath);
        steps.push({
          step: 'Rollback & restore stash',
          status: 'done',
          detail: `Switched back to '${currentBranch}' and restored stash.`,
        });
      }
      return {
        ok: false,
        currentBranch,
        targetBranch: target,
        stashed: false,
        steps,
        error: pullRes.stderr || `Failed to pull origin/${target}.`,
      };
    }
    steps.push({
      step: `Pull latest from origin/${target}`,
      status: 'done',
      detail: `Updated '${target}' from origin.`,
    });
  } else {
    steps.push({
      step: `Pull latest from origin/${target}`,
      status: 'skipped',
      detail: 'No remote origin configured; using local target branch.',
    });
  }

  // Step 3: Switch back to working branch
  const switchBackRes = await runGit(['checkout', currentBranch], repoPath);
  if (!switchBackRes.ok) {
    steps.push({
      step: `Return to '${currentBranch}'`,
      status: 'error',
      detail: switchBackRes.stderr,
    });
    return { ok: false, currentBranch, targetBranch: target, stashed, steps, error: switchBackRes.stderr };
  }
  steps.push({ step: `Return to '${currentBranch}'`, status: 'done', detail: `Checked out '${currentBranch}'.` });

  // Step 4: Rebase onto target branch
  const rebaseRes = await runGit(['rebase', target], repoPath);
  if (!rebaseRes.ok) {
    steps.push({
      step: `Rebase '${currentBranch}' onto '${target}'`,
      status: 'error',
      detail:
        rebaseRes.stderr ||
        rebaseRes.stdout ||
        'Rebase conflict detected. Resolve conflicts in your editor or click "Abort Rebase & Restore Stash".',
    });
    return {
      ok: false,
      conflict: true,
      currentBranch,
      targetBranch: target,
      stashed,
      steps,
      error: 'Rebase conflict detected.',
    };
  }
  steps.push({
    step: `Rebase '${currentBranch}' onto '${target}'`,
    status: 'done',
    detail: `Successfully rebased '${currentBranch}' onto '${target}'.`,
  });

  // Step 5: Restore stash if created
  if (stashed) {
    const popRes = await runGit(['stash', 'pop'], repoPath);
    if (popRes.ok) {
      steps.push({
        step: 'Restore auto-stashed changes',
        status: 'done',
        detail: 'Stashed changes restored cleanly.',
      });
    } else {
      steps.push({
        step: 'Restore auto-stashed changes',
        status: 'error',
        detail: 'Stash applied with conflicts. Please check git status.',
      });
    }
  } else {
    steps.push({
      step: 'Restore auto-stashed changes',
      status: 'skipped',
      detail: 'No stash needed restoration.',
    });
  }

  return {
    ok: true,
    conflict: false,
    currentBranch,
    targetBranch: target,
    stashed,
    steps,
  };
}

export async function abortSmartRebase({ repoPath, originalBranch = '' }) {
  await runGit(['rebase', '--abort'], repoPath);

  if (originalBranch) {
    const curr = await runGit(['rev-parse', '--abbrev-ref', 'HEAD'], repoPath);
    if (curr.ok && curr.stdout.trim() !== originalBranch) {
      await runGit(['checkout', '-f', originalBranch], repoPath);
    }
  }

  const stashList = await runGit(['stash', 'list', '-n', '1'], repoPath);
  let popped = false;
  if (stashList.ok && stashList.stdout.includes('auto-rebase-stash')) {
    const popRes = await runGit(['stash', 'pop'], repoPath);
    popped = popRes.ok;
  }

  return {
    ok: true,
    popped,
    message: popped
      ? 'Rebase aborted and auto-stashed changes restored.'
      : 'Rebase aborted and branch restored.',
  };
}

