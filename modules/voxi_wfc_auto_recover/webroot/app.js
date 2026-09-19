const ctl = '/data/adb/modules/voxi_wfc_auto_recover/bin/voxi-autoctl.sh';
const bridge = document.querySelector('#bridge');
const statusBox = document.querySelector('#status');
const logsBox = document.querySelector('#logs');
const recoverButton = document.querySelector('#recover');

function exec(command) {
  return new Promise((resolve, reject) => {
    if (!window.ksu || typeof window.ksu.exec !== 'function') {
      reject(new Error('当前管理器没有提供 KernelSU/APatch WebUI exec bridge'));
      return;
    }
    const callback = `voxiCallback${Date.now()}${Math.floor(Math.random() * 1000)}`;
    window[callback] = (errno, stdout, stderr) => {
      delete window[callback];
      resolve({ errno, stdout: stdout || '', stderr: stderr || '' });
    };
    window.ksu.exec(command, '{}', callback);
  });
}

async function refresh() {
  try {
    const [status, logs] = await Promise.all([exec(`${ctl} status`), exec(`${ctl} logs`)]);
    bridge.textContent = 'WebUI bridge: READY';
    statusBox.textContent = status.stdout || status.stderr || `exit=${status.errno}`;
    logsBox.textContent = logs.stdout || '暂无恢复记录';
    recoverButton.disabled = false;
  } catch (error) {
    bridge.textContent = error.message;
    recoverButton.disabled = true;
  }
}

recoverButton.addEventListener('click', async () => {
  if (!confirm('只在严格 F8 安全门通过时执行一次固定恢复。继续吗？')) return;
  recoverButton.disabled = true;
  statusBox.textContent = '正在执行安全门与恢复…';
  const result = await exec(`${ctl} recover-now`);
  statusBox.textContent = result.stdout || result.stderr || `exit=${result.errno}`;
  await refresh();
});
document.querySelector('#refresh').addEventListener('click', refresh);
refresh();

