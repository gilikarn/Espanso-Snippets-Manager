// Builds dist/espanso-snippets-manager/: the editor page (with js-yaml inlined,
// so it works offline), both local helpers, the installers and the icons.
import { readFileSync, writeFileSync, mkdirSync, rmSync, copyFileSync, chmodSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const pkg = JSON.parse(readFileSync(join(root, 'package.json'), 'utf8'));
const out = join(root, 'dist', 'espanso-snippets-manager');

rmSync(join(root, 'dist'), { recursive: true, force: true });
mkdirSync(out, { recursive: true });

const jsyamlPath = join(root, 'node_modules', 'js-yaml', 'dist', 'js-yaml.min.js');
const jsyaml = readFileSync(jsyamlPath, 'utf8');
const icon = readFileSync(join(root, 'assets', 'icon.svg'), 'utf8').replace(/\s+/g, ' ').trim();

let html = readFileSync(join(root, 'src', 'index.html'), 'utf8');
const need = ['/*__JSYAML__*/', '__VERSION__', '__FAVICON__'];
for (const token of need) if (!html.includes(token)) throw new Error(`src/index.html is missing ${token}`);
html = html
  .replace('/*__JSYAML__*/', () => jsyaml)
  .replaceAll('__VERSION__', pkg.version)
  .replace('__FAVICON__', 'data:image/svg+xml,' + encodeURIComponent(icon));
writeFileSync(join(out, 'index.html'), html);

const copies = [
  ['src/server.py', 'server.py'],
  ['src/server.ps1', 'server.ps1'],
  ['install/install.ps1', 'install.ps1'],
  ['install/uninstall.ps1', 'uninstall.ps1'],
  ['install/install.sh', 'install.sh'],
  ['install/uninstall.sh', 'uninstall.sh'],
  ['assets/icon.svg', 'icon.svg'],
  ['assets/icon.png', 'icon.png'],
  ['assets/icon.ico', 'icon.ico'],
  ['LICENSE', 'LICENSE'],
  ['README.md', 'README.md'],
];
for (const [from, to] of copies) copyFileSync(join(root, from), join(out, to));
for (const f of ['server.py', 'install.sh', 'uninstall.sh']) chmodSync(join(out, f), 0o755);
writeFileSync(join(out, 'VERSION'), pkg.version + '\n');

console.log(`Built ${pkg.name} ${pkg.version} -> dist/espanso-snippets-manager (${(html.length / 1024).toFixed(0)} KB page)`);
