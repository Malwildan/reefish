const { chromium } = require('playwright');
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');

const base = process.env.PREVIEW_URL || 'http://127.0.0.1:4195';
const configPath = path.resolve(__dirname, '../../config/supabase.local.json');
const config = JSON.parse(fs.readFileSync(configPath, 'utf8'));
assert.ok(typeof config.SUPABASE_URL === 'string' && config.SUPABASE_URL.length > 0,
  'supabase.local.json must configure SUPABASE_URL');
const supabaseUrl = new URL(config.SUPABASE_URL);
const supabaseOrigin = supabaseUrl.origin;
const projectRef = supabaseUrl.hostname.split('.')[0];
const sessionStorageKey = `sb-${projectRef}-auth-token`;
const previewOrigin = new URL(base).origin;
const owner = '11111111-1111-4111-8111-111111111111';
const user = {
  id: owner, aud: 'authenticated', role: 'authenticated', phone: '+6281234567890',
  app_metadata: { provider: 'phone', providers: ['phone'] }, user_metadata: {},
  created_at: '2026-10-15T00:00:00Z',
};
const encode = value => Buffer.from(JSON.stringify(value)).toString('base64url');
function makeSession({ expired = false } = {}) {
  const expires = Math.floor(Date.now() / 1000) + (expired ? -60 : 3600);
  const accessToken = `${encode({ alg: 'HS256', typ: 'JWT' })}.${encode({ sub: owner, exp: expires, role: 'authenticated' })}.local-session-qa`;
  return {
    access_token: accessToken,
    refresh_token: 'local-session-qa-refresh',
    token_type: 'bearer',
    expires_at: expires,
    expires_in: expired ? 0 : 3600,
    user,
  };
}
const validSession = makeSession();
const refreshedSession = makeSession();
const expiredSession = makeSession({ expired: true });
const headers = {
  'access-control-allow-origin': previewOrigin,
  'access-control-allow-credentials': 'true',
  'access-control-allow-methods': 'GET,POST,OPTIONS',
  'access-control-allow-headers': 'authorization, apikey, content-type, x-client-info, accept, prefer',
};

function makeFixture({ refreshMode = 'success', seedSession = null } = {}) {
  const telemetry = { passwordGrants: 0, refreshGrants: 0, logouts: 0, apiMeCalls: 0, blockedSupabasePaths: [], blockedExternalRequests: [] };
  return {
    telemetry,
    async install(context) {
      if (seedSession) {
        await context.addInitScript(({ session, storageKey }) => {
          if (!localStorage.getItem('session-qa-seeded')) {
            localStorage.setItem(storageKey, JSON.stringify(session));
            localStorage.setItem('session-qa-seeded', '1');
          }
        }, { session: seedSession, storageKey: sessionStorageKey });
      }
      await context.route('**/*', async route => {
        const request = route.request();
        const url = new URL(request.url());
        if (url.origin !== supabaseOrigin && url.origin !== previewOrigin) {
          if (url.pathname.endsWith('/weather') || url.pathname.endsWith('/recommendations')) {
            return route.fulfill({ status: 503, contentType: 'application/json',
              headers: { 'access-control-allow-origin': previewOrigin, 'access-control-allow-credentials': 'true' },
              body: JSON.stringify({ error: { code: 'FIXTURE_UNAVAILABLE', message: 'Session QA fixture.' } }) });
          }
          telemetry.blockedExternalRequests.push({ method: request.method(), host: url.host, path: url.pathname });
          return route.abort('blockedbyclient');
        }
        if (url.origin === previewOrigin) return route.continue();
        const json = (body, status = 200) => route.fulfill({
          status, contentType: 'application/json', headers, body: JSON.stringify(body),
        });
        if (request.method() === 'OPTIONS') return route.fulfill({ status: 204, headers });
        if (url.pathname === '/auth/v1/user') return json(user);
        if (url.pathname === '/auth/v1/token') {
          const grantType = url.searchParams.get('grant_type');
          if (grantType === 'password') {
            telemetry.passwordGrants += 1;
            return json(validSession);
          }
          if (grantType === 'refresh_token') {
            telemetry.refreshGrants += 1;
            if (refreshMode === 'network-error') return route.abort('failed');
            return json(refreshedSession);
          }
          telemetry.blockedSupabasePaths.push({ method: request.method(), path: url.pathname, grantType });
          return json({ code: 'FIXTURE_BLOCKED', message: 'Session QA blocked an unexpected auth grant.' }, 404);
        }
        if (url.pathname === '/auth/v1/logout') {
          telemetry.logouts += 1;
          return json({});
        }
        if (url.pathname.endsWith('/rpc/api_me')) {
          telemetry.apiMeCalls += 1;
          return json({
            id: owner, name: 'Nelayan QA', phone: '6281234567890', role: 'nelayan',
            onboarded: true, next_step: 'done',
            boat: { id: '22222222-2222-4222-8222-222222222222', name: 'Kapal QA', engine_hp: 15,
              boat_length_m: 7, fuel_type: 'solar', home_port: { lat: -8.433, lng: 112.683 }, is_default: true },
            stats: { trip_count: 0, baseline_fuel_liters: null, baseline_catch_kg: null },
          });
        }
        if (url.pathname.endsWith('/rpc/api_list_trips')) {
          return json({ data: [], meta: { page: 1, limit: 5, total: 0 },
            summary: { trip_count: 0, total_catch_kg: 0, total_fuel_liters: 0 } });
        }
        telemetry.blockedSupabasePaths.push({ method: request.method(), path: url.pathname });
        return json({ code: 'FIXTURE_BLOCKED', message: 'Session QA blocks unhandled Supabase calls.' }, 404);
      });
    },
  };
}

async function launchPage(browser, fixture, screen = 'login') {
  const context = await browser.newContext({ viewport: { width: 430, height: 932 } });
  await fixture.install(context);
  const page = await context.newPage();
  page.fixtureTelemetry = fixture.telemetry;
  const errors = [];
  page.on('pageerror', error => errors.push(error.message));
  await page.goto(`${base}/?screen=${screen}`, { waitUntil: 'domcontentloaded', timeout: 90000 });
  await page.waitForSelector('flutter-view', { state: 'attached', timeout: 120000 });
  await page.locator('flt-semantics-placeholder').waitFor({ state: 'attached', timeout: 45000 });
  await activateSemantics(page);
  return { context, page, errors };
}

async function activateSemantics(page) {
  const placeholder = page.locator('flt-semantics-placeholder');
  if (await placeholder.count()) await placeholder.evaluate(element => element.click());
}

async function waitForCounts(page, predicate, message) {
  const deadline = Date.now() + 30000;
  while (Date.now() < deadline && !predicate(page.fixtureTelemetry)) await page.waitForTimeout(100);
  assert.ok(predicate(page.fixtureTelemetry), message);
}

async function hasStoredSession(page) {
  return page.evaluate(key => localStorage.getItem(key) != null, sessionStorageKey);
}

async function signIn(page) {
  const phone = page.locator('input[type="tel"]');
  const password = page.locator('input[type="password"]');
  await phone.waitFor({ state: 'visible', timeout: 10000 });
  await phone.fill('81234567890');
  await password.waitFor({ state: 'visible', timeout: 10000 });
  await password.fill('fixture-password-123');
  assert.equal((await password.inputValue()).length, 'fixture-password-123'.length,
    'password text field should receive the synthetic test value');
  await page.getByText('Masuk', { exact: true }).last().click();
  await page.waitForTimeout(1000);
}

async function run() {
  const browser = await chromium.launch({ channel: 'msedge', headless: true });
  const contexts = [];
  const report = {
    checkedAt: new Date().toISOString(),
    previewUrl: base,
    fixtureNotice: 'All Supabase HTTP calls are intercepted. Synthetic fixture sessions and auth responses are used; no production login or writes occur.',
    checks: {},
    limitations: ['This browser test covers Flutter web localStorage persistence only; it does not verify Android Keystore or iOS Keychain behavior.'],
  };
  let current = null;
  let currentFixture = null;
  try {
    const normalFixture = makeFixture();
    currentFixture = normalFixture;
    const normal = await launchPage(browser, normalFixture);
    current = normal;
    contexts.push(normal.context);
    await signIn(normal.page);
    assert.equal(normalFixture.telemetry.passwordGrants, 1, 'the UI sign-in should make one password grant');
    assert.ok(await hasStoredSession(normal.page), 'successful login should persist a browser session');
    await normal.page.screenshot({ path: path.join(__dirname, 'signed-in-after-login-430.png') });
    await normal.page.reload({ waitUntil: 'domcontentloaded' });
    await normal.page.waitForSelector('flutter-view', { state: 'attached', timeout: 120000 });
    await waitForCounts(normal.page, counts => counts.passwordGrants === 1, 'login grant must remain unchanged after reload');
    await normal.page.waitForTimeout(1500);
    assert.ok(await hasStoredSession(normal.page), 'same-origin reload should retain the browser session');
    assert.equal(normalFixture.telemetry.passwordGrants, 1, 'reload must restore the session without another password grant');
    assert.equal(normalFixture.telemetry.refreshGrants, 0, 'a fresh session should not need refresh');
    report.checks.loginAndSameOriginReloadRestore = true;
    report.counts = { passwordGrantsAfterReload: normalFixture.telemetry.passwordGrants, refreshGrantsAfterReload: normalFixture.telemetry.refreshGrants };
    await normal.page.screenshot({ path: path.join(__dirname, 'restored-session-430.png') });

    const refreshFixture = makeFixture({ seedSession: expiredSession });
    const refresh = await launchPage(browser, refreshFixture, 'dashboard');
    contexts.push(refresh.context);
    await waitForCounts(refresh.page, counts => counts.refreshGrants > 0, 'expired persisted session should attempt token refresh');
    await refresh.page.waitForTimeout(1000);
    assert.ok(refreshFixture.telemetry.refreshGrants >= 1, 'expired persisted session should request refresh');
    assert.equal(refreshFixture.telemetry.passwordGrants, 0, 'refresh must not become a password grant');
    assert.ok(await hasStoredSession(refresh.page), 'successful refresh should persist the renewed session');
    const refreshedExpiry = await refresh.page.evaluate(key => {
      try { return JSON.parse(localStorage.getItem(key) || 'null')?.expires_at || null; } catch (_) { return null; }
    }, sessionStorageKey);
    assert.ok(refreshedExpiry > Math.floor(Date.now() / 1000), 'persisted refreshed session should have a future expiry');
    await refresh.page.screenshot({ path: path.join(__dirname, 'refreshed-session-430.png') });
    report.checks.expiredSessionRefreshesAndRestores = true;
    report.expiredSessionRefreshGrants = refreshFixture.telemetry.refreshGrants;

    const outageFixture = makeFixture({ refreshMode: 'network-error', seedSession: expiredSession });
    const outage = await launchPage(browser, outageFixture, 'dashboard');
    contexts.push(outage.context);
    await outage.page.waitForTimeout(1500);
    report.checks.transientRefreshFailure = {
      refreshAttempted: outageFixture.telemetry.refreshGrants > 0,
      sessionRetained: await hasStoredSession(outage.page),
      refreshFailedWithoutSignOut: outageFixture.telemetry.logouts === 0 && outageFixture.telemetry.passwordGrants === 0,
    };
    assert.ok(report.checks.transientRefreshFailure.refreshAttempted, 'transient outage case should try refreshing');
    assert.ok(report.checks.transientRefreshFailure.sessionRetained && report.checks.transientRefreshFailure.refreshFailedWithoutSignOut,
      'refresh outage must preserve cached session data without signing out or attempting password login');
    await outage.page.screenshot({ path: path.join(__dirname, 'refresh-outage-430.png') });

    await normal.page.mouse.click(375, 880);
    await normal.page.waitForTimeout(1000);
    await normal.page.screenshot({ path: path.join(__dirname, 'profile-430.png') });
    await normal.page.mouse.click(215, 452);
    const logoutDeadline = Date.now() + 10000;
    while (Date.now() < logoutDeadline && normalFixture.telemetry.logouts === 0) {
      await normal.page.waitForTimeout(100);
    }
    assert.equal(normalFixture.telemetry.logouts, 1, 'explicit logout should call auth logout once');
    await normal.page.waitForTimeout(1000);
    assert.equal(await hasStoredSession(normal.page), false, 'logout should remove the persisted browser session');
    await normal.page.screenshot({ path: path.join(__dirname, 'signed-out-after-logout-430.png') });
    await normal.page.reload({ waitUntil: 'domcontentloaded' });
    await normal.page.waitForSelector('flutter-view', { state: 'attached', timeout: 120000 });
    await normal.page.waitForTimeout(1000);
    assert.equal(normalFixture.telemetry.passwordGrants, 1, 'logout reload must not silently sign in again');
    assert.equal(await hasStoredSession(normal.page), false, 'logout reload must stay signed out');
    await normal.page.screenshot({ path: path.join(__dirname, 'login-after-logout-reload-430.png') });
    report.checks.loginFormScreenshotAfterLogoutReload = true;
    report.checks.logoutClearsPersistedSession = true;

    for (const fixture of [normalFixture, refreshFixture, outageFixture]) {
      assert.deepEqual(fixture.telemetry.blockedSupabasePaths, [], 'all Supabase requests must be explicitly fixture-handled');
    }
    assert.deepEqual([...normal.errors, ...refresh.errors, ...outage.errors], [], 'browser must have no uncaught page errors');
    report.telemetry = [normalFixture, refreshFixture, outageFixture].map(fixture => ({
      ...fixture.telemetry,
      blockedExternalRequestCount: fixture.telemetry.blockedExternalRequests.length,
      blockedExternalRequests: undefined,
    }));
    report.screenshots = [
      'signed-in-after-login-430.png',
      'restored-session-430.png',
      'refreshed-session-430.png',
      'refresh-outage-430.png',
      'profile-430.png',
      'signed-out-after-logout-430.png',
      'login-after-logout-reload-430.png',
    ];
    fs.writeFileSync(path.join(__dirname, 'verification.json'), JSON.stringify(report, null, 2));
    fs.rmSync(path.join(__dirname, 'failure.json'), { force: true });
    fs.rmSync(path.join(__dirname, 'failure.png'), { force: true });
    console.log(JSON.stringify(report));
  } catch (error) {
    report.failure = error.message;
    if (current) {
      report.failureScreenText = (await current.page.locator('body').innerText().catch(() => '')).slice(0, 2500);
      report.failureTelemetry = currentFixture?.telemetry;
      await current.page.screenshot({ path: path.join(__dirname, 'failure.png') }).catch(() => {});
    }
    fs.writeFileSync(path.join(__dirname, 'failure.json'), JSON.stringify(report, null, 2));
    throw error;
  } finally {
    await Promise.all(contexts.map(context => context.close()));
    await browser.close();
  }
}

run().catch(error => {
  console.error(error.message);
  process.exitCode = 1;
});
