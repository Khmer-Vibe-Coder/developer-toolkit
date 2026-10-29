const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('dtk', {
  getState: (payload) => ipcRenderer.invoke('dtk:getState', payload),
  syncWorkspaceRepo: (payload) => ipcRenderer.invoke('dtk:syncWorkspaceRepo', payload),
  addRepo: (payload) => ipcRenderer.invoke('dtk:addRepo', payload),
  scanWorkspace: (payload) => ipcRenderer.invoke('dtk:scanWorkspace', payload),
  linkBatchRepos: (payload) => ipcRenderer.invoke('dtk:linkBatchRepos', payload),
  removeRepos: (payload) => ipcRenderer.invoke('dtk:removeRepos', payload),
  saveTemplate: (payload) => ipcRenderer.invoke('dtk:saveTemplate', payload),
  removeTemplates: (payload) => ipcRenderer.invoke('dtk:removeTemplates', payload),
  generateReport: (payload) => ipcRenderer.invoke('dtk:generateReport', payload),
  runRebase: (payload) => ipcRenderer.invoke('dtk:runRebase', payload),
  abortRebase: (payload) => ipcRenderer.invoke('dtk:abortRebase', payload),
  pickFolder: (payload) => ipcRenderer.invoke('dtk:pickFolder', payload),
  pickReportOutputDir: (payload) => ipcRenderer.invoke('dtk:pickReportOutputDir', payload),
  saveGuiSettings: (payload) => ipcRenderer.invoke('dtk:saveGuiSettings', payload),
  revealInFolder: (payload) => ipcRenderer.invoke('dtk:revealInFolder', payload),
  openPath: (payload) => ipcRenderer.invoke('dtk:openPath', payload),
});
