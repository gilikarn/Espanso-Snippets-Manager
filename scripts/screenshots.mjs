// Regenerates the README screenshots from the demo fixtures (no personal data).
import { chromium } from '@playwright/test';
import { startApp } from '../tests/e2e/helpers.js';

const app = await startApp();
const browser = await chromium.launch();
try {
  for (const scheme of ['light', 'dark']) {
    const page = await browser.newPage({ viewport: { width: 1240, height: 760 }, deviceScaleFactor: 2, colorScheme: scheme });
    await page.goto(app.url);
    await page.locator('.row', { hasText: ':addr' }).click();
    await page.locator('#pane').evaluate((el) => { el.scrollTop = 0; });
    await page.mouse.move(0, 0);
    await page.screenshot({ path: `docs/screenshot-${scheme}.png` });
    await page.close();
  }
} finally {
  await browser.close();
  app.stop();
}
console.log('Wrote docs/screenshot-light.png and docs/screenshot-dark.png');
