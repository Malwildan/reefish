// Browser-level freshness regression for the mobile grid-policy flow.
// Run with Playwright available in NODE_PATH. Uses synthetic auth and intercepts
// every Supabase request; it creates no account, boat, trip, or backend record.
const { chromium } = require('playwright');
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');

const output = __dirname;
fs.mkdirSync(output, { recursive: true });
const base = process.env.PREVIEW_URL || 'http://127.0.0.1:4195';
const owner = '11111111-1111-4111-8111-111111111111';
const user = {
  id: owner, aud: 'authenticated', role: 'authenticated', phone: '+6280000000000',
  app_metadata: { provider: 'phone', providers: ['phone'] }, user_metadata: {},
  created_at: '2026-10-15T00:00:00Z',
};
const expires = Math.floor(Date.now() / 1000) + 3600;
const encode = value => Buffer.from(JSON.stringify(value)).toString('base64url');
const token = encode({ alg: 'HS256', typ: 'JWT' }) + '.' +
  encode({ sub: owner, exp: expires, role: 'authenticated' }) + '.local-test-signature';
const session = {
  access_token: token, refresh_token: 'local-fixture-refresh', token_type: 'bearer',
  expires_at: expires, expires_in: 3600, user,
};

(async () => {
  const browser = await chromium.launch({ channel: 'msedge', headless: true });
  let page;
  let testTrace = {};
  try {
    const context = await browser.newContext({
      viewport: { width: 430, height: 932 },
      permissions: ['geolocation'],
      geolocation: { latitude: -8.433, longitude: 112.683 },
    });
    await context.addInitScript(({ session }) => {
      if (!localStorage.getItem('grid-freshness-qa-initialized')) {
        localStorage.setItem('sb-upyahsecuorqghcghflg-auth-token', JSON.stringify(session));
        localStorage.setItem('grid-freshness-qa-initialized', '1');
      }
    }, { session });
    page = await context.newPage();
    const pageErrors = [], layoutErrors = [], tileStatuses = [], apiCalls = [];
    let snapshotRequests = 0;
    let settledSnapshotResponses = 0;
    let freshnessPhaseBaseline = null;
    page.on('pageerror', error => pageErrors.push(error.message));
    page.on('console', message => {
      if (/overflowed|EXCEPTION CAUGHT BY RENDERING|RenderFlex/i.test(message.text())) {
        layoutErrors.push(message.text());
      }
    });
    page.on('response', response => {
      if (response.url().includes('tile.openstreetmap.org/')) tileStatuses.push(response.status());
    });

    const profile = {
      id: owner, name: 'Nelayan QA', phone: '6280000000000', role: 'nelayan',
      onboarded: false, next_step: 'boat', boat: null,
      stats: { trip_count: 0, baseline_fuel_liters: null, baseline_catch_kg: null },
    };
    const snapshot = ttlSeconds => {
      // The server clock is deliberately one hour ahead. The expiration window
      // remains valid for the requested TTL and must be mapped to local receipt time.
      const fetched = Date.now() + 60 * 60 * 1000;
      return {
        version: 'grid-freshness-browser-fixture',
        fetched_at: new Date(fetched).toISOString(),
        expires_at: new Date(fetched + ttlSeconds * 1000).toISOString(),
        is_demo: false,
        locks: [],
      };
    };

    await page.route('**/*.supabase.co/**', async route => {
      const request = route.request();
      const url = new URL(request.url());
      const pathname = url.pathname;
      const name = pathname.split('/').pop();
      const headers = {
        'access-control-allow-origin': '*',
        'access-control-allow-headers': '*',
        'access-control-allow-methods': 'GET,POST,OPTIONS',
      };
      if (request.method() === 'OPTIONS') {
        apiCalls.push({ path: pathname, method: 'OPTIONS', status: 204 });
        return route.fulfill({ status: 204, headers });
      }
      const json = (body, status = 200) => route.fulfill({
        status, headers: { ...headers, 'content-type': 'application/json' },
        body: JSON.stringify(body),
      });
      if (pathname === '/auth/v1/user') {
        apiCalls.push({ path: pathname, method: request.method(), status: 200 });
        return json(user);
      }
      if (pathname === '/auth/v1/token') {
        apiCalls.push({ path: pathname, method: request.method(), status: 200 });
        return json(session);
      }
      if (pathname === '/auth/v1/logout') {
        apiCalls.push({ path: pathname, method: request.method(), status: 200 });
        return json({});
      }
      if (name === 'get_grid_lock_snapshot') {
        snapshotRequests++;
        const phaseRequest = freshnessPhaseBaseline == null
          ? null
          : snapshotRequests - freshnessPhaseBaseline;
        if (phaseRequest === 2) {
          apiCalls.push({ path: pathname, method: request.method(), status: 503, fixture: 'expected failure' });
          await json({ code: 'XX000', message: 'UPSTREAM_UNAVAILABLE', hint: 'Fixture temporary failure' }, 503);
          settledSnapshotResponses++;
          return;
        }
        const ttl = phaseRequest === 3 ? 300 : 10;
        apiCalls.push({ path: pathname, method: request.method(), status: 200, ttlSeconds: ttl });
        await json(snapshot(ttl));
        settledSnapshotResponses++;
        return;
      }
      // Profile reads are the only other API surface needed by this screen.
      if (name === 'api_me') {
        apiCalls.push({ path: pathname, method: request.method(), status: 200 });
        return json(profile);
      }
      apiCalls.push({ path: pathname, method: request.method(), status: 404, fixture: 'blocked unhandled request' });
      return json({ code: 'PGRST202', message: 'Fixture blocks unhandled Supabase request' }, 404);
    });

    const button = name => page.getByRole('button', { name, exact: true });
    const body = () => page.locator('body').innerText();
    const screenshot = async name => {
      await page.waitForTimeout(250);
      await page.screenshot({ path: path.join(output, name + '.png') });
    };
    const waitForSnapshotCount = async (count, timeoutMs = 30000) => {
      const deadline = Date.now() + timeoutMs;
      while (settledSnapshotResponses < count && Date.now() < deadline) await page.waitForTimeout(100);
      assert.ok(settledSnapshotResponses >= count,
        `Expected at least ${count} settled grid snapshots; received ${settledSnapshotResponses}`);
    };
    const coordinate = async () => {
      const text = await body();
      const matches = [...text.matchAll(/\d+\.\d{4}° [NS], \d+\.\d{4}° [EW]/g)];
      assert.ok(matches.length, 'Selected fishing point coordinate remains visible');
      return matches[matches.length - 1][0];
    };
    const assertVerified = async label => {
      const text = await body();
      assert.doesNotMatch(text, /belum terverifikasi/i, `${label}: settled status must not fall back to generic unknown`);
      assert.equal(await button('Selesai').isEnabled(), true, `${label}: Selesai must be enabled`);
    };

    await page.goto(base + '/?screen=departure', { waitUntil: 'domcontentloaded', timeout: 90000 });
    await page.waitForSelector('flutter-view', { state: 'attached', timeout: 120000 });
    const semantics = page.locator('flt-semantics-placeholder');
    await semantics.waitFor({ state: 'attached', timeout: 45000 });
    await semantics.evaluate(element => element.click());
    await page.getByText('Simpan Titik Keberangkatan', { exact: true }).waitFor({ timeout: 30000 });
    await button('Pilih Lokasi Saat Ini').click();
    await button('Edit').waitFor();
    await button('Simpan').click();
    await page.getByText('Tempatkan titik ikan?', { exact: true }).waitFor();
    await page.mouse.click(265, 235);
    await page.waitForFunction(
      () => /Selesai|Muat ulang status/.test(document.body.innerText),
      null,
      { timeout: 30000 },
    );
    await screenshot('freshness-selected-before-refresh');
    const selectedCoordinate = await coordinate();

    // Save-and-open-fishing performs a manual refresh. Start the freshness phase
    // only after that request has settled and the selected cell is visible.
    await button('Selesai').waitFor({ timeout: 30000 });
    freshnessPhaseBaseline = snapshotRequests;
    testTrace.phaseBaseline = freshnessPhaseBaseline;
    assert.ok(freshnessPhaseBaseline >= 1, 'The setup snapshot must have completed');
    await assertVerified('before automatic renewal');
    assert.equal(await coordinate(), selectedCoordinate, 'Automatic refresh must preserve the selected fishing point');
    await screenshot('freshness-before-auto-refresh');

    // The first request after the baseline is the automatic renewal and must
    // succeed. The next automatic renewal fails exactly once.
    await waitForSnapshotCount(freshnessPhaseBaseline + 1, 30000);
    await button('Selesai').waitFor({ timeout: 15000 });
    await assertVerified('after first automatic refresh');
    assert.equal(await coordinate(), selectedCoordinate, 'Automatic refresh must preserve the selected fishing point');
    await screenshot('freshness-auto-refresh');

    // Baseline+2 is the expected failed automatic renewal. Wait for the retry affordance,
    // then prove that the app does not spin in an automatic retry loop.
    await button('Muat ulang status').waitFor({ timeout: 30000 });
    assert.equal(snapshotRequests, freshnessPhaseBaseline + 2, 'Expected exactly one failed automatic renewal');
    await page.waitForTimeout(1500);
    assert.equal(snapshotRequests, freshnessPhaseBaseline + 2, 'A failed policy fetch must not hot-retry automatically');
    assert.equal(await coordinate(), selectedCoordinate, 'A failed refresh must preserve the selected point');
    testTrace.beforeManualRecovery = { snapshotRequests, settledSnapshotResponses };
    await screenshot('freshness-refresh-failed');

    const closeSummary = button('Tutup ringkasan petak');
    if (await closeSummary.count()) {
      await closeSummary.click({ force: true });
      await closeSummary.waitFor({ state: 'detached', timeout: 5000 });
    }
    await button('Muat ulang status').click();
    await waitForSnapshotCount(freshnessPhaseBaseline + 3, 10000);
    testTrace.afterManualRecovery = { snapshotRequests, settledSnapshotResponses };
    await button('Selesai').waitFor({ timeout: 15000 });
    await assertVerified('after manual recovery');
    await waitForSnapshotCount(freshnessPhaseBaseline + 3, 1000);
    assert.equal(await coordinate(), selectedCoordinate, 'Manual recovery must preserve the selected point');
    await screenshot('freshness-manual-recovery');

    assert.deepEqual(pageErrors, []);
    assert.deepEqual(layoutErrors, []);
    const unexpectedCalls = apiCalls.filter(call => call.fixture === 'blocked unhandled request');
    assert.deepEqual(unexpectedCalls, [], 'All Supabase traffic must be intercepted by the local fixture');
    const report = {
      checkedAt: new Date().toISOString(), previewUrl: base,
      scenario: 'server clock +1h; 10s setup/renewal snapshots; second automatic renewal failure; manual recovery',
      policyRequests: snapshotRequests, phaseBaseline: freshnessPhaseBaseline, selectedCoordinate,
      policyResponses: apiCalls.filter(call => call.path.endsWith('/get_grid_lock_snapshot')),
      errors: pageErrors, layoutErrors, tileRequests: tileStatuses.length,
      tileStatuses: [...new Set(tileStatuses)],
      checks: {
        syntheticAuthOnly: true, allSupabaseHttpIntercepted: true,
        serverClockSkewAccepted: true, automaticRenewalAfterTtl: true,
        baselinePlusOneAutoRenewalFresh: true, baselinePlusTwoAutoRenewalFailed: true,
        baselinePlusThreeManualRecoveryFresh: true,
        noUnknownAfterSettledRefresh: true, selectionPreservedOnRefresh: true,
        failedRefreshShowsManualRetry: true, noAutomaticRetryLoop: true,
        manualRecoveryRestoresFreshStatus: true, noFinishOrJourneySubmitted: true,
        noPageOrLayoutErrors: true,
      },
      evidenceFiles: [
        'freshness-selected-before-refresh.png', 'freshness-before-auto-refresh.png',
        'freshness-auto-refresh.png', 'freshness-refresh-failed.png',
        'freshness-manual-recovery.png',
      ],
      fixtureNotice: 'Synthetic auth and all Supabase HTTP responses were intercepted locally. No production account, boat, trip, or policy was changed.',
      nativeAndroid: 'not tested',
    };
    fs.mkdirSync(output, { recursive: true });
    fs.writeFileSync(path.join(output, 'verification.json'), JSON.stringify(report, null, 2));
    console.log(JSON.stringify(report));
  } catch (error) {
    if (page) {
      fs.mkdirSync(output, { recursive: true });
      await page.screenshot({ path: path.join(output, 'failure.png') });
      fs.writeFileSync(path.join(output, 'failure.txt'), await page.locator('body').innerText());
      fs.writeFileSync(path.join(output, 'failure-details.json'), JSON.stringify({
        error: error.message, ...testTrace,
      }, null, 2));
    }
    throw error;
  } finally {
    await browser.close();
  }
})().catch(error => { console.error(error); process.exitCode = 1; });
