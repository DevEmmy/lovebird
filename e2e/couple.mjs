// Two-person end-to-end test on the LIVE site:
// A signs up + creates a circle, B signs up + joins with the code,
// then they play Tic-Tac-Love and Love Pong and make a voice call.
import { chromium } from 'playwright';
import fs from 'node:fs';

const BASE = process.env.SITE_URL || 'https://devemmy.github.io/lovebird/';
const RUN = process.env.RUN_ID || String(Date.now()).slice(-6);
const OUT = 'e2e/out';
fs.mkdirSync(OUT, { recursive: true });
const report = { steps: [], console: { A: [], B: [] }, supabase: { A: [], B: [] } };
const step = (s) => { console.log('STEP', s); report.steps.push(s); };

const browser = await chromium.launch({
  args: ['--use-fake-ui-for-media-stream', '--use-fake-device-for-media-stream', '--autoplay-policy=no-user-gesture-required', '--disable-features=WebRtcHideLocalIpsWithMdns'],
});

async function person(tag) {
  const ctx = await browser.newContext({ viewport: { width: 412, height: 860 }, locale: 'en-US', timezoneId: 'Africa/Lagos', permissions: ['camera', 'microphone'] });
  await ctx.addInitScript(() => {
    const Orig = window.RTCPeerConnection;
    window.__rtc = [];
    window.RTCPeerConnection = function (...a) {
      const pc = new Orig(...a);
      const rec = { conn: 'new', ice: 'new', sig: 'stable', cands: 0, remoteCands: 0, tracks: 0, log: [] };
      window.__rtc.push(rec);
      pc.addEventListener('connectionstatechange', () => { rec.conn = pc.connectionState; rec.log.push('conn:' + pc.connectionState); });
      pc.addEventListener('iceconnectionstatechange', () => { rec.ice = pc.iceConnectionState; rec.log.push('ice:' + pc.iceConnectionState); });
      pc.addEventListener('signalingstatechange', () => { rec.sig = pc.signalingState; rec.log.push('sig:' + pc.signalingState); });
      pc.addEventListener('icecandidate', (e) => { if (e.candidate) { rec.cands++; rec.log.push('cand:' + e.candidate.candidate.split(' ').slice(4, 8).join(' ')); } });
      pc.addEventListener('track', () => { rec.tracks++; });
      const add = pc.addIceCandidate.bind(pc);
      pc.addIceCandidate = (c, ...r) => { rec.remoteCands++; return add(c, ...r).catch((err) => { rec.log.push('addIce ERR ' + err); throw err; }); };
      return pc;
    };
    window.RTCPeerConnection.prototype = Orig.prototype;
    Object.setPrototypeOf(window.RTCPeerConnection, Orig);
  });
  const page = await ctx.newPage();
  page.on('console', (m) => { if (m.type() === 'error' || m.text().startsWith('[call]')) report.console[tag].push(m.text().slice(0, 1500)); });
  page.on('pageerror', (e) => report.console[tag].push('pageerror: ' + String(e.stack || e).slice(0, 1200)));
  page.on('response', async (r) => {
    if (r.url().includes('supabase.co') && r.status() >= 400) {
      let body = '';
      try { body = (await r.text()).slice(0, 300); } catch {}
      report.supabase[tag].push(`${r.status()} ${r.url().replace(/^https:\/\/[^/]+/, '').slice(0, 100)} ${body}`);
    }
  });
  return page;
}

let shot = 0;
const snap = async (page, name) => page.screenshot({ path: `${OUT}/${String(++shot).padStart(2, '0')}-${name}.png` });
const wait = (p, ms) => p.waitForTimeout(ms);
const semantics = async (p) => { await p.evaluate(() => document.querySelector('flt-semantics-placeholder')?.click()); await wait(p, 600); };
const tap = async (p, re, timeout = 10000) => { await semantics(p); await p.getByRole('button', { name: re }).or(p.getByText(re)).first().click({ timeout }); };
const typeInto = async (p, re, text) => { await p.getByRole('textbox', { name: re }).first().click({ timeout: 10000 }); await wait(p, 200); await p.keyboard.type(text, { delay: 10 }); };
// Visible text plus accessibility labels (Flutter puts many labels in aria-label).
// Tap the invite banner's Join button (top-right of the screen).
const tapJoin = async (p) => {
  try { await tap(p, /^Join$/, 3000); } catch { await p.mouse.click(367, 31); }
};
const text = async (p) => p.evaluate(() => {
  const host = document.querySelector('flt-semantics-host');
  if (!host) return '';
  const labels = [...host.querySelectorAll('[aria-label]')].map((e) => e.getAttribute('aria-label'));
  return host.innerText + ' | ' + labels.join(' | ');
}).catch(() => '');

async function signUp(p, name, email) {
  await p.goto(BASE, { waitUntil: 'load', timeout: 60000 });
  await wait(p, 8000);
  await tap(p, /Create our world/i);
  await wait(p, 2000);
  await semantics(p);
  await typeInto(p, /Display name/i, name);
  await typeInto(p, /Email/i, email);
  await typeInto(p, /Password/i, 'Lovebird' + RUN + 'x');
  await tap(p, /Date of birth|Select/i);
  await wait(p, 1200);
  await semantics(p);
  await p.getByRole('textbox').first().click();
  await p.keyboard.press('Control+A');
  await p.keyboard.type('01/15/1995');
  await tap(p, /^OK$/i);
  await wait(p, 800);
  await semantics(p);
  await p.getByRole('checkbox').first().click();
  await tap(p, /Create account/i);
  await wait(p, 7000);
}

const A = await person('A');
const B = await person('B');
try {
  step('A signs up');
  await signUp(A, 'Mercy', `eolaosebikan60+lbA${RUN}@gmail.com`);
  step('A creates circle');
  await tap(A, /Create Love Circle/i);
  await wait(A, 5000);
  await semantics(A);
  const t = await text(A);
  const spaced = t.match(/Invitation code ((?:[A-Z0-9] ){7}[A-Z0-9])/);
  const code = spaced ? spaced[1].replace(/ /g, '') : (t.match(/\b[A-HJ-NP-Z2-9]{8}\b/) || [])[0];
  report.waitingText = t.slice(0, 300);
  report.code = code;
  await snap(A, 'A-waiting');
  if (!code) throw new Error('No invite code shown');

  step('B signs up');
  await signUp(B, 'David', `eolaosebikan60+lbB${RUN}@gmail.com`);
  step('B joins with code');
  await semantics(B);
  await typeInto(B, /ABCD2345|code/i, code);
  await tap(B, /Find invitation/i);
  await wait(B, 3000);
  await snap(B, 'B-found-invite');
  await tap(B, /Join Mercy/i);
  await wait(B, 7000);
  await wait(A, 1000);
  await snap(B, 'B-home');
  await snap(A, 'A-home-after-join');
  report.homeA = (await text(A)).slice(0, 400);
  report.homeB = (await text(B)).slice(0, 400);

  step('A starts Tic-Tac-Love');
  await A.goto(BASE + '#/games', { waitUntil: 'load' });
  await wait(A, 7000);
  await tap(A, /Tic-Tac-Love/i);
  await wait(A, 4000);
  report.gameUrl = A.url();
  step('B taps Join on the invite banner');
  await wait(B, 2000);
  await semantics(B);
  report.bInvite = (await text(B)).includes('wants to play');
  await snap(B, 'B-invite-banner');
  await tapJoin(B);
  await wait(B, 6000);
  step('A plays centre square');
  await tap(A, /Empty square 5/i);
  await wait(A, 3000);
  await wait(B, 1000);
  await semantics(B);
  report.ticB = (await text(B)).slice(0, 300);
  await snap(A, 'A-tictac');
  await snap(B, 'B-tictac-after-A-move');
  step('B plays a corner');
  await tap(B, /Empty square 1/i);
  await wait(B, 3000);
  await semantics(A);
  report.ticA = (await text(A)).slice(0, 300);
  await snap(A, 'A-tictac-after-B-move');

  step('Love Pong');
  await A.goto(BASE + '#/games', { waitUntil: 'load' });
  await wait(A, 7000);
  await B.goto(BASE + '#/home', { waitUntil: 'load' });
  await wait(B, 7000);
  await tap(A, /Love Pong/i);
  await wait(B, 4000);
  await tapJoin(B);
  await wait(B, 7000);
  // move B's paddle around a bit
  const box = await B.locator('flt-glass-pane, flutter-view').first().boundingBox().catch(() => null);
  if (box) {
    for (let i = 0; i < 6; i++) { await B.mouse.move(box.x + box.width * (0.2 + i * 0.12), box.y + box.height * 0.7); await wait(B, 300); }
  }
  await snap(A, 'A-pong');
  await snap(B, 'B-pong');
  await wait(A, 4000);
  await snap(A, 'A-pong-later');

  step('Voice call: A calls B');
  await A.goto(BASE + '#/chat', { waitUntil: 'load' });
  await B.goto(BASE + '#/home', { waitUntil: 'load' });
  await wait(A, 8000);
  await wait(B, 2000);
  await tap(A, /Voice call/i);
  await wait(B, 4000);
  await semantics(B);
  report.bIncoming = (await text(B)).slice(0, 200);
  await snap(B, 'B-incoming-call');
  await tap(B, /^Accept$/i);
  await wait(A, 4000);
  report.rtcEarlyA = await A.evaluate(() => window.__rtc);
  report.rtcEarlyB = await B.evaluate(() => window.__rtc);
  await wait(A, 12000);
  await semantics(A);
  await semantics(B);
  report.callA = (await text(A)).slice(0, 200);
  report.callB = (await text(B)).slice(0, 200);
  report.webrtc = await A.evaluate(() => ({ media: document.querySelectorAll('video,audio').length }));
  report.rtcA = await A.evaluate(() => window.__rtc);
  report.rtcB = await B.evaluate(() => window.__rtc);
  await snap(A, 'A-in-call');
  await snap(B, 'B-in-call');
  await tap(A, /^End$/i);
  await wait(A, 2000);
  step('done');
} catch (e) {
  report.error = String(e).slice(0, 1500);
  await snap(A, 'A-error').catch(() => {});
  await snap(B, 'B-error').catch(() => {});
}
fs.writeFileSync(`${OUT}/report.json`, JSON.stringify(report, null, 2));
await browser.close();
// rerun6 envelope-fix
