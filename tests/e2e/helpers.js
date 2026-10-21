// Starts a private copy of the app (Python helper + built page) on a free port
// with a fresh copy of the fixtures, so every test gets clean files.
import { spawn } from 'node:child_process';
import { cpSync, mkdtempSync, readFileSync, rmSync, writeFileSync, readdirSync, utimesSync } from 'node:fs';
import { createServer } from 'node:net';
import { tmpdir } from 'node:os';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const dist = join(root, 'dist', 'espanso-snippets-manager');

function freePort() {
  return new Promise((resolve) => {
    const s = createServer();
    s.listen(0, '127.0.0.1', () => { const { port } = s.address(); s.close(() => resolve(port)); });
  });
}

export async function startApp() {
  const tmp = mkdtempSync(join(tmpdir(), 'esm-e2e-'));
  const config = join(tmp, 'espanso');
  const backups = join(tmp, 'backups');
  cpSync(join(root, 'tests', 'fixtures', 'espanso'), config, { recursive: true });
  const port = await freePort();
  const py = process.env.PYTHON || (process.platform === 'win32' ? 'python' : 'python3');
  const proc = spawn(py, [join(dist, 'server.py'), '--no-browser', '--port', String(port), '--config-dir', config, '--backup-dir', backups], { stdio: 'ignore' });
  const url = `http://localhost:${port}/`;
  for (let i = 0; i < 100; i++) {
    try { const r = await fetch(url + 'api/ping'); if (r.ok) break; } catch { /* not up yet */ }
    await new Promise((r) => setTimeout(r, 100));
  }
  const match = join(config, 'match');
  return {
    url, match, backups,
    read: (name) => readFileSync(join(match, name), 'utf8'),
    write: (name, text) => writeFileSync(join(match, name), text),
    touch: (name) => { const t = new Date(Date.now() + 5000); utimesSync(join(match, name), t, t); },
    listBackups: () => { try { return readdirSync(backups); } catch { return []; } },
    stop: () => { proc.kill(); rmSync(tmp, { recursive: true, force: true }); },
  };
}
