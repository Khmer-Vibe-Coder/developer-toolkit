import fs from 'node:fs/promises';
import path from 'node:path';
import os from 'node:os';

export function getDefaultConfigDir() {
  return process.env.GIT_REPORT_CONFIG_DIR || path.join(os.homedir(), '.config', 'developer-toolkit');
}

function stripPipes(value) {
  return String(value ?? '').replace(/\|/g, '').trim();
}

export async function ensureConfigDir(configDir = getDefaultConfigDir()) {
  await fs.mkdir(configDir, { recursive: true });
  return configDir;
}

export async function loadRepos(configDir = getDefaultConfigDir()) {
  const reposFile = path.join(configDir, 'repos.conf');
  let raw = '';
  try {
    raw = await fs.readFile(reposFile, 'utf8');
  } catch (err) {
    if (err.code === 'ENOENT') return [];
    throw err;
  }

  const repos = [];
  for (const line of raw.split(/\r?\n/)) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith('#')) continue;
    const parts = trimmed.split('|');
    const rName = (parts[0] || '').trim();
    if (!rName) continue;

    let rType = (parts[1] || '').trim();
    let rPath = (parts[2] || '').trim();
    let rSource = (parts[3] || '').trim();

    // Backward compatibility for 2-column format: name|path
    if (!rPath && rType) {
      rPath = rType;
      rType = 'local';
      rSource = rPath;
    }
    if (!rSource) {
      rSource = rPath;
    }
    repos.push({
      name: rName,
      type: rType === 'remote' ? 'remote' : 'local',
      path: rPath,
      source: rSource,
    });
  }
  return repos;
}

export async function saveRepo(configDir, entry) {
  await ensureConfigDir(configDir);
  const newName = stripPipes(entry.name);
  const newType = entry.type === 'remote' ? 'remote' : 'local';
  const newPath = stripPipes(entry.path);
  const newSource = stripPipes(entry.source || entry.path);

  if (!newName || !newPath) {
    throw new Error('Repository name and path are required');
  }

  const existing = await loadRepos(configDir);
  const outLines = [];
  let updated = false;

  for (const item of existing) {
    if (item.name === newName || item.path === newPath) {
      if (!updated) {
        outLines.push(`${newName}|${newType}|${newPath}|${newSource}`);
        updated = true;
      }
    } else {
      outLines.push(`${item.name}|${item.type}|${item.path}|${item.source}`);
    }
  }

  if (!updated) {
    outLines.push(`${newName}|${newType}|${newPath}|${newSource}`);
  }

  const reposFile = path.join(configDir, 'repos.conf');
  const tmpFile = `${reposFile}.tmp`;
  await fs.writeFile(tmpFile, outLines.length ? `${outLines.join('\n')}\n` : '', 'utf8');
  await fs.rename(tmpFile, reposFile);
}

export async function removeRepos(configDir, names = []) {
  await ensureConfigDir(configDir);
  const nameSet = new Set(names.map((n) => String(n).trim()));
  const existing = await loadRepos(configDir);
  const remotesDir = path.join(configDir, 'remotes');
  const outLines = [];
  let removed = 0;

  for (const item of existing) {
    if (nameSet.has(item.name)) {
      removed += 1;
      if (item.type === 'remote' && item.path && item.path.startsWith(remotesDir + path.sep)) {
        await fs.rm(item.path, { recursive: true, force: true }).catch(() => {});
      }
    } else {
      outLines.push(`${item.name}|${item.type}|${item.path}|${item.source}`);
    }
  }

  const reposFile = path.join(configDir, 'repos.conf');
  const tmpFile = `${reposFile}.tmp`;
  await fs.writeFile(tmpFile, outLines.length ? `${outLines.join('\n')}\n` : '', 'utf8');
  await fs.rename(tmpFile, reposFile);
  return removed;
}

export async function loadTemplates(configDir = getDefaultConfigDir()) {
  const templatesFile = path.join(configDir, 'templates.conf');
  let raw = '';
  try {
    raw = await fs.readFile(templatesFile, 'utf8');
  } catch (err) {
    if (err.code === 'ENOENT') return [];
    throw err;
  }

  const templates = [];
  for (const line of raw.split(/\r?\n/)) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith('#')) continue;
    const parts = trimmed.split('|');
    const name = (parts[0] || '').trim();
    if (!name) continue;
    const reposCsv = (parts[1] || '').trim();
    const branchSpec = (parts[2] || '').trim() || 'develop';
    const authorMode = (parts[3] || '').trim() || 'all';
    const authorPattern = (parts[4] || '').trim();
    const datePreset = (parts[5] || '').trim() || 'ask';

    templates.push({
      name,
      repos: reposCsv ? reposCsv.split(',').map((r) => r.trim()).filter(Boolean) : [],
      branchSpec,
      authorMode,
      authorPattern,
      datePreset,
    });
  }
  return templates;
}

export async function saveTemplate(configDir, tpl) {
  await ensureConfigDir(configDir);
  const cleanName = stripPipes(tpl.name).replace(/\s+/g, '_');
  if (!cleanName) {
    throw new Error('Template name cannot be empty');
  }
  const reposList = Array.isArray(tpl.repos)
    ? tpl.repos.map((r) => stripPipes(r)).filter(Boolean)
    : stripPipes(tpl.repos)
        .split(',')
        .map((r) => r.trim())
        .filter(Boolean);
  const reposCsv = reposList.join(',');
  const branchSpec = stripPipes(tpl.branchSpec || 'develop') || 'develop';
  const authorMode = stripPipes(tpl.authorMode || 'all') || 'all';
  const authorPattern = stripPipes(tpl.authorPattern || '');
  const datePreset = stripPipes(tpl.datePreset || 'ask') || 'ask';

  const existing = await loadTemplates(configDir);
  const outLines = [];
  let updated = false;

  for (const item of existing) {
    if (item.name === cleanName) {
      outLines.push(`${cleanName}|${reposCsv}|${branchSpec}|${authorMode}|${authorPattern}|${datePreset}`);
      updated = true;
    } else {
      outLines.push(
        `${item.name}|${item.repos.join(',')}|${item.branchSpec}|${item.authorMode}|${item.authorPattern}|${item.datePreset}`
      );
    }
  }

  if (!updated) {
    outLines.push(`${cleanName}|${reposCsv}|${branchSpec}|${authorMode}|${authorPattern}|${datePreset}`);
  }

  const templatesFile = path.join(configDir, 'templates.conf');
  const tmpFile = `${templatesFile}.tmp`;
  await fs.writeFile(tmpFile, outLines.length ? `${outLines.join('\n')}\n` : '', 'utf8');
  await fs.rename(tmpFile, templatesFile);
  return cleanName;
}

export async function removeTemplates(configDir, names = []) {
  await ensureConfigDir(configDir);
  const nameSet = new Set(names.map((n) => String(n).trim()));
  const existing = await loadTemplates(configDir);
  const outLines = [];
  let removed = 0;

  for (const item of existing) {
    if (nameSet.has(item.name)) {
      removed += 1;
    } else {
      outLines.push(
        `${item.name}|${item.repos.join(',')}|${item.branchSpec}|${item.authorMode}|${item.authorPattern}|${item.datePreset}`
      );
    }
  }

  const templatesFile = path.join(configDir, 'templates.conf');
  const tmpFile = `${templatesFile}.tmp`;
  await fs.writeFile(tmpFile, outLines.length ? `${outLines.join('\n')}\n` : '', 'utf8');
  await fs.rename(tmpFile, templatesFile);
  return removed;
}

export function resolveDefaultReportOutputDir(callerDir = '') {
  const cleanCaller = String(callerDir || '').trim().replace(/\\/g, '/');
  const home = os.homedir().replace(/\\/g, '/');
  if (
    !cleanCaller ||
    cleanCaller === '/' ||
    cleanCaller === home ||
    /^[A-Za-z]:\/?$/.test(cleanCaller) ||
    cleanCaller.toLowerCase().includes('/windows/system32')
  ) {
    return path.join(os.homedir(), 'Documents', 'DeveloperToolkit-Reports');
  }
  return path.join(callerDir, 'report');
}

export async function loadGuiSettings(configDir = getDefaultConfigDir(), callerDir = '') {
  const settingsFile = path.join(configDir, 'gui-settings.json');
  const fallbackDir = resolveDefaultReportOutputDir(callerDir);
  const defaultFavorites = ['develop', 'main'];
  try {
    const raw = await fs.readFile(settingsFile, 'utf8');
    const parsed = JSON.parse(raw);
    const rawFavs = Array.isArray(parsed.favoriteBranches) ? parsed.favoriteBranches : defaultFavorites;
    const favoriteBranches = Array.from(new Set(rawFavs.map((b) => String(b).trim()).filter(Boolean)));
    return {
      reportOutputDir: parsed.reportOutputDir || fallbackDir,
      favoriteBranches: favoriteBranches.length ? favoriteBranches : defaultFavorites,
    };
  } catch {
    return {
      reportOutputDir: fallbackDir,
      favoriteBranches: defaultFavorites,
    };
  }
}

export async function saveGuiSettings(configDir = getDefaultConfigDir(), settings = {}, callerDir = '') {
  await ensureConfigDir(configDir);
  const settingsFile = path.join(configDir, 'gui-settings.json');
  let currentRaw = {};
  try {
    currentRaw = JSON.parse(await fs.readFile(settingsFile, 'utf8'));
  } catch {}

  const next = {
    ...currentRaw,
    ...settings,
  };
  if (Array.isArray(next.favoriteBranches)) {
    next.favoriteBranches = Array.from(
      new Set(next.favoriteBranches.map((b) => String(b).trim()).filter(Boolean))
    );
  }
  const tmpFile = `${settingsFile}.tmp`;
  await fs.writeFile(tmpFile, JSON.stringify(next, null, 2), 'utf8');
  await fs.rename(tmpFile, settingsFile);
  return loadGuiSettings(configDir, callerDir);
}

