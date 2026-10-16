// Run with Playwright available in NODE_PATH. No real auth or backend writes.
const { chromium } = require('playwright');
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');

const output = __dirname;
const base = process.env.PREVIEW_URL || 'http://127.0.0.1:4194';
const gps = { latitude: -8.433, longitude: 112.683 };

(async () => {
  const browser = await chromium.launch({ channel: 'msedge', headless: true });
  let lastPage;
  try {
    const context = await browser.newContext({
      viewport: { width: 430, height: 932 },
      permissions: ['geolocation'], geolocation: gps,
    });
    const page = await context.newPage();
    lastPage = page;
    const errors = [], tiles = [];
    let mode = 'open', lockedCell, requests = 0;
    page.on('pageerror', error => errors.push(error.message));
    page.on('response', response => {
      if (response.url().includes('tile.openstreetmap.org/')) tiles.push(response.status());
    });
    await page.route('**/rest/v1/rpc/get_grid_lock_snapshot', async route => {
      requests++;
      if (mode === 'failed') return route.abort('failed');
      const now = Date.now();
      await route.fulfill({ contentType: 'application/json', body: JSON.stringify({
        version: 'focus-browser-fixture',
        fetched_at: new Date(now - 1000).toISOString(),
        expires_at: new Date(now + 300000).toISOString(),
        is_demo: mode === 'unknown',
        locks: mode === 'locked' ? [{ cell_id: lockedCell, reason: 'Pembatasan fixture QA' }] : [],
      }) });
    });
    const enableSemantics = async () => {
      await page.waitForSelector('flutter-view', { state: 'attached', timeout: 90000 });
      const placeholder = page.locator('flt-semantics-placeholder');
      await placeholder.waitFor({ state: 'attached', timeout: 30000 });
      await placeholder.evaluate(node => node.click());
    };
    const screenshot = async name => {
      await page.waitForTimeout(350);
      await page.screenshot({ path: path.join(output, name + '.png') });
    };
    const body = () => page.locator('body').innerText();
    const button = name => page.getByRole('button', { name, exact: true });
    const stored = () => page.evaluate(() => Object.fromEntries(
      Object.entries(localStorage).filter(([key]) => /reefish\.(departure|fishing)-point/.test(key))
    ));

    await page.goto(base + '/?screen=departure', { waitUntil: 'domcontentloaded', timeout: 90000 });
    await enableSemantics();
    await page.getByText('Simpan Titik Keberangkatan', { exact: true }).waitFor();
    await page.waitForTimeout(1500);
    await screenshot('focus-1-430');
    await button('Pilih Lokasi Saat Ini').click();
    await button('Edit').waitFor();
    await screenshot('focus-2-430');
    await button('Simpan').click();
    await page.getByText('Tempatkan titik ikan?', { exact: true }).waitFor();
    const departureStorage = await stored();
    const departureKey = Object.keys(departureStorage).find(key => key.includes('departure-point'));
    assert.ok(departureKey, 'Departure must be persisted before selecting fishing point');
    await screenshot('focus-3-empty-430');
    await page.mouse.click(265, 235);
    await button('Selesai').waitFor();
    await screenshot('focus-3-selected-430');
    await button('Selesai').click();
    await page.waitForFunction(() => Object.keys(localStorage).some(key => key.includes('reefish.fishing-point')));
    const savedStorage = await stored();
    const fishingKey = Object.keys(savedStorage).find(key => key.includes('fishing-point'));
    const decode = value => { const parsed = JSON.parse(value); return typeof parsed === 'string' ? JSON.parse(parsed) : parsed; };
    const selection = decode(savedStorage[fishingKey]);
    const departure = decode(savedStorage[departureKey]);
    assert.equal(savedStorage[departureKey], departureStorage[departureKey]);
    assert.notEqual(selection.cell_id, departure.cell_id);
    assert.equal(selection.departure.cell_id, departure.cell_id);
    lockedCell = selection.cell_id;
    await screenshot('focus-3-saved-430');
    await page.waitForTimeout(4500);

    // Policy can change between choosing a point and submitting it.
    mode = 'locked';
    await button('Selesai').click();
    await page.waitForFunction(() => document.body.innerText.includes('terkunci'));
    assert.deepEqual(await stored(), savedStorage, 'Locked point must not overwrite stored choice');
    await screenshot('focus-3-locked-430');

    await button('Kembali').click();
    await button('Edit').waitFor();
    await button('Kembali').click();
    await page.getByText('Simpan Titik Keberangkatan', { exact: true }).waitFor();
    await button('Lihat Peta').click();
    await page.mouse.click(135, 310);
    await button('Gunakan titik ini').click();
    await page.waitForTimeout(350);
    if (await page.getByText('Simpan Titik Keberangkatan', { exact: true }).count()) await button('Simpan').click();
    await button('Edit').waitFor();
    await page.waitForTimeout(350);
    mode = 'unknown';
    await button('Simpan').click();
    await page.getByText('Tempatkan titik ikan?', { exact: true }).waitFor();
    await page.mouse.click(265, 235);
    await page.waitForFunction(() => document.body.innerText.includes('belum terverifikasi'));
    await screenshot('focus-3-unknown-430');
    mode = 'open';
    await button('Muat ulang status').click();
    await button('Selesai').waitFor();
    mode = 'failed';
    await button('Selesai').click();
    await button('Muat ulang status').waitFor();
    assert.equal((await stored())[fishingKey], savedStorage[fishingKey],
      'Failed policy refresh must not reuse earlier open status to save');
    await page.setViewportSize({ width: 360, height: 640 });
    await screenshot('focus-3-360');
    await button('Kembali').click();
    await screenshot('focus-2-360');
    await button('Edit').click();
    await screenshot('focus-1-360');
    await page.reload({ waitUntil: 'domcontentloaded', timeout: 90000 });
    await enableSemantics();
    await button('Edit').waitFor();
    await screenshot('focus-2-restored-360');
    assert.deepEqual(errors, []);
    assert.ok(requests >= 4);
    const report = {
      checkedAt: new Date().toISOString(), previewUrl: base,
      frames: ['194:749','194:1076','194:1014'],
      errors, tileRequests: tiles.length, tileStatuses: [...new Set(tiles)], policyRequests: requests,
      checks: { gpsToConfirmation: true, fishingSelection: true, separateStorage: true,
        lockedAtSubmitRejected: true, unknownRejected: true, policyRetry: true,
        failedRefreshRejected: true, backAndEdit: true,
        manualSelection: true, compactViewport: true, restoredDeparture: true },
      fixtures: { gps, policy: 'Intercepted HTTP fixture; not official access policy or field data' },
      limitations: ['No Android device or native permission test', 'No real login, auth mutation or backend write',
        'Selesai stores a local planned selection; next trip form is outside this slice'],
    };
    fs.writeFileSync(path.join(output, 'verification.json'), JSON.stringify(report, null, 2));
    console.log(JSON.stringify(report));
  } catch (error) {
    if (lastPage) {
      await lastPage.screenshot({ path: path.join(output, 'failure.png') });
      fs.writeFileSync(path.join(output, 'failure.txt'), await lastPage.locator('body').innerText());
    }
    throw error;
  } finally { await browser.close(); }
})().catch(error => { console.error(error); process.exitCode = 1; });
