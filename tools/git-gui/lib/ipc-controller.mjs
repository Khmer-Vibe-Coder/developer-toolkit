import fs from 'node:fs/promises';
import path from 'node:path';
import os from 'node:os';
import { fileURLToPath } from 'node:url';
import {
  getDefaultConfigDir,
  loadRepos,
  saveRepo,
  removeRepos,
  loadTemplates,
  saveTemplate,
  removeTemplates,
  loadGuiSettings,
  saveGuiSettings,
} from './config-store.mjs';
import { DATE_PRESETS, resolveDateRange } from './date-presets.mjs';
import {
  inspectRepo,
  scanWorkspace,
  linkRepository,
  generateReport,
  runSmartRebase,
  abortSmartRebase,
  resolveGitRoot,
} from './git-ops.mjs';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const TOOLKIT_ROOT = path.resolve(__dirname, '../../..');

async function readToolkitVersion() {
  try {
    const v = await fs.readFile(path.join(TOOLKIT_ROOT, 'VERSION'), 'utf8');
    return v.trim() || '2.0.0';
  } catch {
    return '2.0.0';
  }
}

async function getEnrichedRepos(configDir) {
  const rawRepos = await loadRepos(configDir);
  return Promise.all(rawRepos.map((r) => inspectRepo(r)));
}

export function createIpcHandlers({
  configDir = getDefaultConfigDir(),
  callerDir = process.env.DTK_CALLER_DIR || process.cwd(),
  dialogApi = null,
  shellApi = null,
  getMainWindow = () => null,
} = {}) {
  let currentCaller = callerDir && callerDir !== '/' ? callerDir : os.homedir();

  return {
    async getState(payload = {}) {
      if (payload.callerDir) {
        currentCaller = payload.callerDir;
      }
      const normalizedCaller = currentCaller.replace(/\\/g, '/');
      const gitRoot = await resolveGitRoot(currentCaller);

      let rawRepos = await loadRepos(configDir);
      if (gitRoot) {
        const alreadyLinked = rawRepos.some(
          (r) => r.path === gitRoot || r.source === gitRoot
        );
        if (!alreadyLinked) {
          const projectName = path.basename(gitRoot);
          await linkRepository({
            target: gitRoot,
            customName: projectName,
            configDir,
            callerDir: currentCaller,
          });
          rawRepos = await loadRepos(configDir);
        }
      }

      const [version, repos, templates, settings] = await Promise.all([
        readToolkitVersion(),
        Promise.all(
          rawRepos.map(async (r) => {
            const enriched = await inspectRepo(r);
            const isCurrent = gitRoot
              ? enriched.path === gitRoot
              : normalizedCaller === enriched.path || normalizedCaller.startsWith(`${enriched.path}/`);
            return {
              ...enriched,
              isCurrentWorkspace: Boolean(isCurrent),
            };
          })
        ),
        loadTemplates(configDir),
        loadGuiSettings(configDir, currentCaller),
      ]);

      const activeRepo =
        repos.find((r) => r.isCurrentWorkspace) ||
        repos.find(
          (r) =>
            r.type === 'local' &&
            (normalizedCaller === r.path || normalizedCaller.startsWith(`${r.path}/`))
        ) ||
        repos.find((r) => r.type === 'local');

      return {
        version,
        platform: process.platform,
        callerDir: normalizedCaller,
        configDir,
        reportOutputDir: settings.reportOutputDir,
        favoriteBranches: settings.favoriteBranches,
        currentRepoName: activeRepo ? activeRepo.name : '',
        repos,
        templates,
        datePresets: DATE_PRESETS,
      };
    },

    async syncWorkspaceRepo(payload = {}) {
      if (payload.callerDir) {
        currentCaller = payload.callerDir;
      }
      return this.getState();
    },

    async addRepo(payload = {}) {
      const linked = await linkRepository({
        target: payload.target || currentCaller,
        customName: payload.name || '',
        configDir,
        callerDir: currentCaller,
      });
      const repos = await getEnrichedRepos(configDir);
      return { linked, repos };
    },

    async scanWorkspace(payload = {}) {
      const found = await scanWorkspace(
        payload.scanDir || currentCaller,
        4,
        currentCaller
      );
      const existing = await loadRepos(configDir);
      const existingPaths = new Set(existing.map((r) => r.path));
      const candidates = found.map((item) => ({
        ...item,
        alreadyLinked: existingPaths.has(item.path),
      }));

      if (payload.linkAll) {
        for (const item of found) {
          await saveRepo(configDir, {
            name: item.name,
            type: 'local',
            path: item.path,
            source: item.path,
          });
        }
      }

      const repos = await getEnrichedRepos(configDir);
      return { candidates, repos };
    },

    async linkBatchRepos(payload = {}) {
      const items = Array.isArray(payload.repos) ? payload.repos : [];
      for (const item of items) {
        if (item && item.path) {
          await saveRepo(configDir, {
            name: item.name || path.basename(item.path),
            type: 'local',
            path: item.path,
            source: item.path,
          });
        }
      }
      const repos = await getEnrichedRepos(configDir);
      return { repos };
    },

    async removeRepos(payload = {}) {
      const removed = await removeRepos(configDir, payload.names || []);
      const repos = await getEnrichedRepos(configDir);
      return { removed, repos };
    },

    async saveTemplate(payload = {}) {
      const savedName = await saveTemplate(configDir, payload);
      const templates = await loadTemplates(configDir);
      return { savedName, templates };
    },

    async removeTemplates(payload = {}) {
      const removed = await removeTemplates(configDir, payload.names || []);
      const templates = await loadTemplates(configDir);
      return { removed, templates };
    },

    async generateReport(payload = {}) {
      const allRepos = await loadRepos(configDir);
      const requestedNames = Array.isArray(payload.repos) ? payload.repos : [];
      const selectedRepos = requestedNames.length
        ? requestedNames
            .map((name) => allRepos.find((r) => r.name === name))
            .filter(Boolean)
        : allRepos;

      const dateRange = resolveDateRange({
        preset: payload.preset || '',
        fromDate: payload.fromDate || '',
        toDate: payload.toDate || '',
      });

      const settings = await loadGuiSettings(configDir, currentCaller);

      return generateReport({
        repos: selectedRepos,
        branchSpec: payload.branchSpec || 'develop',
        fromDate: dateRange.fromDate,
        toDate: dateRange.toDate,
        presetLabel: dateRange.label,
        authorMode: payload.authorMode || 'all',
        authorPattern: payload.authorPattern || '',
        doFetch: Boolean(payload.doFetch),
        includeMerges: Boolean(payload.includeMerges),
        detailed: Boolean(payload.detailed),
        saveToDisk: payload.saveToDisk !== false,
        outputExt: payload.outputExt || 'md',
        customOutput: payload.customOutput || '',
        outputDir: payload.outputDir || settings.reportOutputDir,
        callerDir: currentCaller,
      });
    },

    async runRebase(payload = {}) {
      const allRepos = await loadRepos(configDir);
      const targetRepo = allRepos.find(
        (r) => r.name === payload.repoName || r.path === payload.repoPath
      );
      const repoPath =
        payload.repoPath || (targetRepo ? targetRepo.path : currentCaller);

      const result = await runSmartRebase({
        repoPath,
        targetBranch: payload.targetBranch || 'develop',
      });
      const repos = await getEnrichedRepos(configDir);
      return { ...result, repos };
    },

    async abortRebase(payload = {}) {
      const allRepos = await loadRepos(configDir);
      const targetRepo = allRepos.find(
        (r) => r.name === payload.repoName || r.path === payload.repoPath
      );
      const repoPath =
        payload.repoPath || (targetRepo ? targetRepo.path : currentCaller);

      const result = await abortSmartRebase({
        repoPath,
        originalBranch: payload.originalBranch || '',
      });
      const repos = await getEnrichedRepos(configDir);
      return { ...result, repos };
    },

    async pickFolder(payload = {}) {
      if (!dialogApi || typeof dialogApi.showOpenDialog !== 'function') {
        return { canceled: true, folderPath: '' };
      }
      const win = getMainWindow();
      const opts = {
        title: payload.title || 'Select Folder',
        defaultPath: payload.defaultPath || currentCaller,
        properties: ['openDirectory', 'createDirectory'],
      };
      const res = win
        ? await dialogApi.showOpenDialog(win, opts)
        : await dialogApi.showOpenDialog(opts);
      if (res.canceled || !res.filePaths || !res.filePaths.length) {
        return { canceled: true, folderPath: '' };
      }
      return { canceled: false, folderPath: res.filePaths[0].replace(/\\/g, '/') };
    },

    async pickReportOutputDir(payload = {}) {
      const current = await loadGuiSettings(configDir, currentCaller);
      const picked = await this.pickFolder({
        title: 'Choose Report Output Folder',
        defaultPath: payload.defaultPath || current.reportOutputDir,
      });
      if (picked.canceled || !picked.folderPath) {
        return { canceled: true, reportOutputDir: current.reportOutputDir };
      }
      const saved = await saveGuiSettings(configDir, {
        reportOutputDir: picked.folderPath,
      }, currentCaller);
      return { canceled: false, reportOutputDir: saved.reportOutputDir };
    },

    async saveGuiSettings(payload = {}) {
      return saveGuiSettings(configDir, payload, currentCaller);
    },

    async revealInFolder(payload = {}) {
      const targetPath = String(payload.targetPath || '').trim();
      if (!targetPath || !shellApi) return { ok: false };
      if (typeof shellApi.showItemInFolder === 'function') {
        shellApi.showItemInFolder(path.normalize(targetPath));
        return { ok: true };
      }
      return { ok: false };
    },

    async openPath(payload = {}) {
      const targetPath = String(payload.targetPath || '').trim();
      if (!targetPath || !shellApi) return { ok: false };
      if (typeof shellApi.openPath === 'function') {
        await shellApi.openPath(path.normalize(targetPath));
        return { ok: true };
      }
      return { ok: false };
    },
  };
}
