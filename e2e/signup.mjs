// Drives the LIVE web app like a person would and records what happens.
// Output: e2e/out/*.png screenshots + report.json (console errors, failed requests, steps).
import { chromium } from 'playwright';
import fs from 'node:fs';

const BASE = process.env.SITE_URL || 'https://devemmy.github.io/lovebird/';
const EMAIL = process.env.TEST_EMAIL;
const PASSWORD = 'Lovebird' + Date.now().toString().slice(-6) + 'x';
const OUT = 'e2e/out';
fs.mkdirSync(OUT, { recursive: true });

const report = { base: BASE, steps: [], console: [], failedRequests: [], supabase: [] };
const step = (s) => { console.log('STEP', s); report.steps.push(s); };

const browser = await chromium.launch();
const page = await browser.newPage({ viewport: { width: 412, height: 915 }, deviceScaleFactor: 1, locale: 'en-US', timezoneId: 'Africa/Lagos' });
page.on('console', (m) => { if (['error', 'warning'].includes(m.type())) report.console.push(`${m.type()}: ${m.text()}`.slice(0, 600)); });
page.on('pageerror', (e) => report.console.push('pageerror: ' + String(e.stack || e).slice(0, 4000)));
page.on('requestfailed', (r) => report.failedRequests.push(`${r.url().slice(0, 160)} ${r.failure()?.errorText}`));
page.on('response', async (r) => {
  if (r.url().includes('supabase.co')) {
    let body = '';
    try { if (r.status() >= 400) body = (await r.text()).slice(0, 400); } catch {}
    report.supabase.push(`${r.status()} ${r.request().method()} ${r.url().replace(/^https:\/\/[^/]+/, '').slice(0, 120)} ${body}`);
  }
});

let shot = 0;
const snap = async (name) => { await page.screenshot({ path: `${OUT}/${String(++shot).padStart(2, '0')}-${name}.png` }); };
const wait = (ms) => page.waitForTimeout(ms);

async function enableSemantics() {
  // Flutter web exposes an accessibility tree on demand; turn it on so we can find buttons/fields by label.
  await page.evaluate(() => {
    const p = document.querySelector('flt-semantics-placeholder');
    if (p) p.click();
  });
  await wait(800);
}

async function tapText(re) {
  const el = page.getByRole('button', { name: re }).or(page.getByText(re)).first();
  await el.click({ timeout: 8000 });
}

async function typeInto(labelRe, text) {
  const field = page.getByRole('textbox', { name: labelRe }).first();
  await field.click({ timeout: 8000 });
  await wait(250);
  await page.keyboard.type(text, { delay: 15 });
  await wait(150);
}

try {
  step('open site');
  await page.goto(BASE + '?nocache=' + Date.now(), { waitUntil: 'load', timeout: 60000 });
  report.navigatorLanguage = await page.evaluate(() => [navigator.language, navigator.languages]);
  report.bootstrap = await page.evaluate(async () => (await (await fetch('flutter_bootstrap.js', { cache: 'no-store' })).text()).slice(0, 300));
  await wait(9000);
  await snap('landing');
  // Can the live site reach the Internet Archive film catalogue (CORS)?
  report.archive = await page.evaluate(async () => {
    try {
      const r = await fetch('https://archive.org/advancedsearch.php?q=collection%3A%28feature_films%29&fl%5B%5D=identifier&fl%5B%5D=title&rows=3&output=json&sort%5B%5D=downloads+desc');
      const j = await r.json();
      const id = j.response.docs[0].identifier;
      const m = await (await fetch('https://archive.org/metadata/' + id)).json();
      const mp4 = (m.files || []).filter(f => (f.name || '').endsWith('.mp4')).map(f => f.name + ' [' + f.format + ']');
      return { ok: true, titles: j.response.docs.map(d => d.title), firstId: id, mp4: mp4.slice(0, 3) };
    } catch (e) { return { ok: false, error: String(e) }; }
  });
  await enableSemantics();

  step('tap Create our world');
  await tapText(/Create our world/i);
  await wait(2500);
  await enableSemantics();
  await snap('signup-empty');

  step('fill sign-up form');
  await typeInto(/Display name/i, 'Mercy');
  await typeInto(/Email/i, EMAIL);
  await typeInto(/Password/i, PASSWORD);
  await snap('signup-typed');

  step('date of birth');
  await tapText(/Date of birth|Select/i);
  await wait(1500);
  await enableSemantics();
  await snap('dob-picker');
  // Input-mode date picker: type a date then OK.
  const dateField = page.getByRole('textbox').first();
  await dateField.click();
  await page.keyboard.press('Control+A');
  await page.keyboard.type('01/15/1995');
  await wait(300);
  await tapText(/^OK$/i);
  await wait(1200);
  await snap('dob-set');

  step('agree checkbox');
  await page.getByRole('checkbox').first().click({ timeout: 8000 });
  await wait(400);
  await snap('agreed');

  step('submit');
  await tapText(/Create account/i);
  await wait(8000);
  await enableSemantics();
  await snap('after-submit');
  report.afterSubmitText = (await page.locator('flt-semantics-host, body').first().innerText().catch(() => '')).slice(0, 1500);

  step('create love circle');
  await tapText(/Create Love Circle/i);
  await wait(6000);
  await enableSemantics();
  await snap('after-create-circle');
  report.afterCircleText = (await page.locator('flt-semantics-host, body').first().innerText().catch(() => '')).slice(0, 1500);

  step('done');
} catch (e) {
  report.error = String(e).slice(0, 1500);
  await snap('error').catch(() => {});
}

fs.writeFileSync(`${OUT}/report.json`, JSON.stringify(report, null, 2));
await browser.close();
