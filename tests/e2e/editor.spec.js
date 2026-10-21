import { test, expect } from '@playwright/test';
import yaml from 'js-yaml';
import { startApp } from './helpers.js';

let app;
test.beforeEach(async ({ page }) => {
  app = await startApp();
  page.on('pageerror', (err) => { throw err; });
  await page.goto(app.url);
  await expect(page.locator('#fileName')).toHaveText('work.yml');
});
test.afterEach(() => app.stop());

const matchesOf = (text) => yaml.load(text).matches;
const row = (page, text) => page.locator('.row', { hasText: text }).first();

test('opens the first regular file and lists its snippets', async ({ page }) => {
  await expect(page.locator('#count')).toHaveText('11 snippets');
  await expect(page.locator('#saveTxt')).toHaveText('Saved');
  await expect(page.locator('#saveBtn')).toBeDisabled();
  await expect(page.locator('#status')).toBeVisible();
});

test('opening and saving nothing leaves files untouched', async ({ page }) => {
  for (const name of ['work.yml', 'base.yml', 'work/email.yml']) {
    await page.click('#fileBtn');
    await page.locator('.menu button', { hasText: name }).first().click();
    await row(page, '').click();
    await expect(page.locator('#saveBtn')).toBeDisabled();
  }
  expect(app.listBackups()).toEqual([]);
});

test('edits a snippet and writes valid Espanso YAML', async ({ page }) => {
  await row(page, 'btw').click();
  await page.locator('#trigIn').fill('bytheway');
  await page.keyboard.press('Enter');
  await page.locator('#txt').fill('by the way!');
  await page.locator('#bSeg button[data-b="left"]').click();
  await page.locator('label.toggle').click();
  await page.locator('#label').fill('BTW');
  await page.keyboard.press('Control+s');
  await expect(page.locator('#saveTxt')).toHaveText('Saved');

  const m = matchesOf(app.read('work.yml')).find((x) => x.label === 'BTW');
  expect(m).toEqual({ triggers: ['btw', 'bytheway'], label: 'BTW', replace: 'by the way!', left_word: true, propagate_case: true });
  expect(app.listBackups().length).toBe(1);
  // untouched entries keep their exact meaning
  const all = matchesOf(app.read('work.yml'));
  expect(all.find((x) => x.trigger === ':shrug').replace).toBe('¯\\_(ツ)_/¯');
  expect(all.find((x) => x.trigger === ':greet')).toEqual({ trigger: ':greet', form: 'Hey [[name]], how are you?' });
  expect(all.find((x) => x.trigger === ':sig').replace).toBe('Best regards,\nJane Doe\nExample Corp');
});

test('keeps the comment block at the top of a file', async ({ page }) => {
  await page.click('#fileBtn');
  await page.locator('.menu button', { hasText: 'base.yml' }).click();
  await row(page, ':espanso').click();
  await page.locator('#txt').fill('Hello!');
  await page.keyboard.press('Control+s');
  await expect(page.locator('#saveTxt')).toHaveText('Saved');
  const text = app.read('base.yml');
  expect(text.startsWith('# espanso match file\n# This comment block at the top of the file should survive a save.\n')).toBe(true);
  const ms = matchesOf(text);
  expect(ms[0]).toEqual({ trigger: ':espanso', replace: 'Hello!' });
  expect(ms[1].vars[0]).toEqual({ name: 'mydate', type: 'date', params: { format: '%m/%d/%Y' } });
  expect(ms[2].regex).toBe(':hi(?P<person>\\w+)\\.');
});

test('inserts a date variable and defines it', async ({ page }) => {
  await row(page, 'omw').click();
  await page.locator('#txt').click();
  await page.keyboard.press('End');
  await page.click('#insBtn');
  await page.locator('.menu button', { hasText: '{{date_iso}}' }).click();
  await expect(page.locator('#pvWrap')).toContainText(/on my way\d{4}-\d{2}-\d{2}/);
  await page.keyboard.press('Control+s');
  await expect(page.locator('#saveTxt')).toHaveText('Saved');
  const m = matchesOf(app.read('work.yml')).find((x) => x.trigger === 'omw');
  expect(m.replace).toBe('on my way{{date_iso}}');
  expect(m.vars).toEqual([{ name: 'date_iso', type: 'date', params: { format: '%Y-%m-%d' } }]);
});

test('a new snippet needs a shortcut before saving', async ({ page }) => {
  await page.keyboard.press('Control+n');
  await page.locator('#txt').fill('Hello world');
  await page.keyboard.press('Control+s');
  await expect(page.locator('.toast.err')).toContainText('at least one shortcut');
  await page.locator('#trigIn').fill(':hw');
  await page.keyboard.press('Enter');
  await page.keyboard.press('Control+s');
  await expect(page.locator('#saveTxt')).toHaveText('Saved');
  expect(matchesOf(app.read('work.yml'))[0]).toEqual({ trigger: ':hw', replace: 'Hello world' });
});

test('merges snippets with identical text, with undo', async ({ page }) => {
  await expect(page.locator('#banner')).toContainText('Some snippets have identical text');
  await page.click('#mergeBtn');
  await expect(page.locator('#count')).toHaveText('10 snippets');
  await page.locator('.toast.act button').click();
  await expect(page.locator('#count')).toHaveText('11 snippets');
  await page.click('#mergeBtn');
  await page.keyboard.press('Control+s');
  await expect(page.locator('#saveTxt')).toHaveText('Saved');
  const kr = matchesOf(app.read('work.yml')).find((x) => x.replace === 'Kind regards');
  expect(kr.triggers).toEqual([':kr', ':kreg']);
});

test('delete can be undone', async ({ page }) => {
  await row(page, 'teh').click();
  await page.click('#delBtn');
  await expect(page.locator('#count')).toHaveText('10 snippets');
  await page.locator('.toast.act button').click();
  await expect(page.locator('#count')).toHaveText('11 snippets');
  await expect(page.locator('#saveBtn')).toBeDisabled();
});

test('warns instead of overwriting changes made elsewhere', async ({ page }) => {
  await row(page, 'btw').click();
  await page.locator('#txt').fill('changed here');
  app.touch('work.yml');
  await page.keyboard.press('Control+s');
  await expect(page.locator('.modal h3')).toContainText('changed on disk');
  await page.locator('.modal [data-a="mine"]').click();
  await expect(page.locator('#saveTxt')).toHaveText('Saved');
  expect(matchesOf(app.read('work.yml')).find((x) => x.trigger === 'btw').replace).toBe('changed here');
});

test('search filters by shortcut, text and label', async ({ page }) => {
  await page.locator('#q').fill('baker');
  await expect(page.locator('.row')).toHaveCount(1);
  await page.locator('#q').fill('office address');
  await expect(page.locator('.row')).toHaveCount(1);
  await page.locator('#q').fill(':sig');
  await expect(page.locator('.row')).toHaveCount(1);
  await page.keyboard.press('Escape');
  await expect(page.locator('.row')).toHaveCount(11);
});

test('try-it box expands like Espanso', async ({ page }) => {
  await row(page, 'btw').click();
  const t = page.locator('#tryIn');
  await t.click();
  await page.keyboard.type('Teh cat, btw ');
  await expect(t).toHaveValue('The cat, by the way ');
  await t.fill('');
  await page.keyboard.type('xbtw ');
  await expect(t).toHaveValue('xbtw ');
  await t.fill('');
  await page.keyboard.type(':meet');
  await expect(t).toHaveValue('Does  work for a quick call?');
  await expect(t).toHaveJSProperty('selectionStart', 5);
});

test('creates a new file in a subfolder', async ({ page }) => {
  await page.click('#fileBtn');
  await page.locator('.menu button', { hasText: 'New file' }).click();
  await page.locator('#nfName').fill('personal/home');
  await page.keyboard.press('Enter');
  await expect(page.locator('#fileName')).toHaveText('personal/home.yml');
  expect(app.read('personal/home.yml')).toBe('matches: []\n');
});

test('hides installed packages and flags underscore files', async ({ page }) => {
  await page.click('#fileBtn');
  await expect(page.locator('.menu')).not.toContainText('package.yml');
  await page.locator('.menu button', { hasText: '_private.yml' }).click();
  await expect(page.locator('#pane')).toContainText("aren't loaded by Espanso automatically");
});

test('read-only view for advanced snippets', async ({ page }) => {
  await row(page, ':greet').click();
  await expect(page.locator('#pane')).toContainText("doesn't cover (form)");
  await expect(page.locator('#txt')).toHaveCount(0);
});
