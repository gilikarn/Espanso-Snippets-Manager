// Renders docs/social-preview.png (1280x640), the card GitHub shows when the repo link is shared.
// Upload it under Settings > General > Social preview. Regenerate with: npm run screenshots && node scripts/social-preview.mjs
import { chromium } from '@playwright/test';
import { readFileSync } from 'node:fs';

const icon = readFileSync('assets/icon.svg', 'utf8');
const shot = 'data:image/png;base64,' + readFileSync('docs/screenshot-light.png').toString('base64');

const html = `<!doctype html><html><head><style>
  body{margin:0;width:1280px;height:640px;overflow:hidden;font-family:"Segoe UI",system-ui,-apple-system,sans-serif;
       background:linear-gradient(135deg,#f3f3ff 0%,#e7e7fb 100%);color:#1c2230;position:relative}
  .text{position:absolute;left:72px;top:96px;width:520px}
  .icon{width:96px;height:96px}
  h1{font-size:60px;line-height:1.05;margin:28px 0 18px;letter-spacing:-.02em}
  p{font-size:27px;line-height:1.4;margin:0;color:#4a5165}
  .tags{margin-top:34px;display:flex;gap:10px}
  .tags span{font-size:19px;padding:7px 14px;border-radius:999px;background:#fff;color:#4a4ac4;font-weight:600;box-shadow:0 1px 2px rgba(0,0,0,.06)}
  .shot{position:absolute;left:650px;top:84px;width:860px;border-radius:16px;box-shadow:0 24px 60px rgba(40,40,120,.22);border:1px solid #d9dbe6}
</style></head><body>
  <div class="text">
    <div class="icon">${icon.replace('<svg ', '<svg width="96" height="96" ')}</div>
    <h1>Espanso Snippets Manager</h1>
    <p>A fast, friendly editor for your Espanso snippets. Local, offline, open source.</p>
    <div class="tags"><span>Windows</span><span>macOS</span><span>Linux</span></div>
  </div>
  <img class="shot" src="${shot}">
</body></html>`;

const browser = await chromium.launch();
const page = await browser.newPage({ viewport: { width: 1280, height: 640 } });
await page.setContent(html);
await page.screenshot({ path: 'docs/social-preview.png' });
await browser.close();
console.log('Wrote docs/social-preview.png');
