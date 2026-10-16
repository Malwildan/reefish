const { chromium } = require('playwright');
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');

const base = process.env.PREVIEW_URL || 'http://127.0.0.1:4195';
const apiBase = process.env.GO_API_URL;
const owner = '11111111-1111-4111-8111-111111111111';
const homePort = { lat: -8.433, lng: 112.683 };
const configPath = path.resolve(__dirname, '../../config/supabase.local.json');

function readPublicSupabaseConfig() {
  const config = JSON.parse(fs.readFileSync(configPath, 'utf8'));
  assert.ok(typeof config.SUPABASE_URL === 'string' && config.SUPABASE_URL.length > 0,
    'supabase.local.json must configure SUPABASE_URL');
  assert.ok(typeof config.SUPABASE_PUBLISHABLE_KEY === 'string' && config.SUPABASE_PUBLISHABLE_KEY.length > 0,
    'supabase.local.json must configure SUPABASE_PUBLISHABLE_KEY');
  return new URL(config.SUPABASE_URL);
}

assert.ok(apiBase, 'Set GO_API_URL to the API base compiled into the Flutter preview.');
const goApi = new URL(apiBase);
assert.ok(goApi.protocol === 'https:' || ['127.0.0.1', 'localhost', '::1'].includes(goApi.hostname),
  'GO_API_URL must use HTTPS or a loopback host.');
const goPath = goApi.pathname.replace(/\/+$/, '');
assert.ok(goPath.endsWith('/api/v1'), 'GO_API_URL must end in /api/v1.');
const supabaseOrigin = readPublicSupabaseConfig().origin;
const previewOrigin = new URL(base).origin;
const metricPatterns = {
  temperature: /31\.2\s*°C/,
  wind: /14\.4\s*km\/jam/,
  wave: /1\.1\s*m/,
};

const user = {
  id: owner,
  aud: 'authenticated',
  role: 'authenticated',
  phone: '+6280000000000',
  app_metadata: { provider: 'phone', providers: ['phone'] },
  user_metadata: {},
  created_at: '2026-10-15T00:00:00Z',
};
const expires = Math.floor(Date.now() / 1000) + 3600;
const encode = value => Buffer.from(JSON.stringify(value)).toString('base64url');
const token = `${encode({ alg: 'HS256', typ: 'JWT' })}.${encode({ sub: owner, exp: expires, role: 'authenticated' })}.local-weather-fixture`;
const session = {
  access_token: token,
  refresh_token: 'local-weather-fixture-refresh',
  token_type: 'bearer',
  expires_at: expires,
  expires_in: 3600,
  user,
};
const boat = {
  id: '22222222-2222-4222-8222-222222222222',
  name: 'Kapal QA',
  engine_hp: 15,
  boat_length_m: 7,
  fuel_type: 'solar',
  home_port: homePort,
  is_default: true,
};
const supabaseHeaders = {
  'access-control-allow-origin': previewOrigin,
  'access-control-allow-credentials': 'true',
  'access-control-allow-methods': 'GET,POST,OPTIONS',
  'access-control-allow-headers': 'authorization, apikey, content-type, x-client-info, accept, prefer',
};
const apiHeaders = {
  'access-control-allow-origin': previewOrigin,
  'access-control-allow-credentials': 'true',
  'access-control-allow-methods': 'GET,OPTIONS',
  'access-control-allow-headers': 'authorization, accept, content-type',
};

function weatherResponse({ waveHeightM = 1.1 } = {}) {
  const now = new Date();
  const hour = new Date(now);
  hour.setUTCMinutes(0, 0, 0);
  return {
    data: {
      location: homePort,
      fetched_at: now.toISOString(),
      current: {
        time: hour.toISOString(),
        weather_code: 0,
        weather_label: 'Cerah',
        temp_c: 31.2,
        wind_speed_ms: 4,
        wind_dir_deg: 90,
        wind_dir_label: 'T',
        wave_height_m: waveHeightM,
        risk: waveHeightM == null ? 'unknown' : 'low',
      },
      hourly: [],
      warnings: [],
    },
  };
}

async function makeDashboard(browser, mode, telemetry) {
  const context = await browser.newContext({
    viewport: { width: 430, height: 932 },
    permissions: ['geolocation'],
    geolocation: { latitude: homePort.lat, longitude: homePort.lng },
  });
  await context.addInitScript(({ session }) => {
    if (!localStorage.getItem('journey-weather-qa-initialized')) {
      localStorage.setItem('sb-upyahsecuorqghcghflg-auth-token', JSON.stringify(session));
      localStorage.setItem('journey-weather-qa-initialized', '1');
    }
  }, { session });
  const page = await context.newPage();
  const errors = [];
  const layoutErrors = [];
  const requestCounts = { weather: 0, recommendations: 0 };
  page.on('pageerror', error => errors.push(error.message));
  page.on('console', message => {
    if (/overflowed|EXCEPTION CAUGHT BY RENDERING|RenderFlex/i.test(message.text())) {
      layoutErrors.push(message.text());
    }
  });

  await page.route('**/*', async route => {
    const request = route.request();
    const url = new URL(request.url());
    const json = (body, status = 200, headers = {}) => route.fulfill({
      status,
      contentType: 'application/json',
      headers,
      body: JSON.stringify(body),
    });

    if (url.origin === supabaseOrigin) {
      if (request.method() === 'OPTIONS') {
        return route.fulfill({ status: 204, headers: supabaseHeaders });
      }
      const headers = { ...supabaseHeaders };
      if (url.pathname === '/auth/v1/user') return json(user, 200, headers);
      if (url.pathname === '/auth/v1/token') return json(session, 200, headers);
      if (url.pathname === '/auth/v1/logout') return json({}, 200, headers);
      const rpc = url.pathname.split('/').pop();
      if (rpc === 'api_me') {
        return json({
          id: owner,
          name: 'Nelayan QA',
          phone: '6280000000000',
          role: 'nelayan',
          onboarded: true,
          next_step: 'done',
          boat,
          stats: { trip_count: 0, baseline_fuel_liters: null, baseline_catch_kg: null },
        }, 200, headers);
      }
      if (rpc === 'api_list_trips') {
        return json({
          data: [],
          meta: { page: 1, limit: 5, total: 0 },
          summary: { trip_count: 0, total_catch_kg: 0, total_fuel_liters: 0 },
        }, 200, headers);
      }
      if (rpc === 'get_grid_lock_snapshot') {
        return json({
          version: 'weather-fixture',
          fetched_at: new Date().toISOString(),
          expires_at: new Date(Date.now() + 300000).toISOString(),
          is_demo: false,
          locks: [],
        }, 200, headers);
      }
      telemetry.blockedSupabasePaths.push({ method: request.method(), path: url.pathname });
      return json({ code: 'FIXTURE_BLOCKED', message: 'Weather QA blocks unhandled Supabase calls.' }, 404, headers);
    }

    const goOrigin = goApi.origin;
    const isGoApi = url.origin === goOrigin && url.pathname.startsWith(`${goPath}/`);
    const isWeather = url.pathname.endsWith('/weather');
    const isRecommendations = url.pathname.endsWith('/recommendations');
    if ((isWeather || isRecommendations) && !isGoApi) {
      telemetry.goBaseMismatches.push({ path: url.pathname });
      return json({ error: { code: 'FIXTURE_BLOCKED', message: 'The app Go API base does not match GO_API_URL.' } }, 502, apiHeaders);
    }
    if (isGoApi && request.method() === 'OPTIONS') {
      return route.fulfill({ status: 204, headers: apiHeaders });
    }
    if (isGoApi && url.pathname === `${goPath}/recommendations`) {
      telemetry.recommendations += 1;
      requestCounts.recommendations += 1;
      return json({ error: { code: 'FIXTURE_UNAVAILABLE', message: 'Recommendation fixture unavailable.' } }, 503, apiHeaders);
    }
    if (isGoApi && url.pathname === `${goPath}/weather`) {
      telemetry.weather += 1;
      requestCounts.weather += 1;
      const lat = Number(url.searchParams.get('lat'));
      const lng = Number(url.searchParams.get('lng'));
      assert.ok(Math.abs(lat - homePort.lat) < 0.00001, `weather latitude should use fixture home port, got ${lat}`);
      assert.ok(Math.abs(lng - homePort.lng) < 0.00001, `weather longitude should use fixture home port, got ${lng}`);
      if (mode === 'unavailable') {
        return json({ error: { code: 'WEATHER_UNAVAILABLE', message: 'Fixture weather unavailable.' } }, 503, apiHeaders);
      }
      const data = mode === 'missing-marine' ? weatherResponse({ waveHeightM: null }) : weatherResponse();
      return json(data, 200, apiHeaders);
    }
    if (url.origin === goOrigin && url.pathname.startsWith(goPath)) {
      telemetry.unexpectedGoPaths.push({ method: request.method(), path: url.pathname });
      return json({ error: { code: 'FIXTURE_BLOCKED', message: 'Weather QA only fixtures recommendations and weather.' } }, 404, apiHeaders);
    }
    return route.continue();
  });

  try {
    await page.goto(`${base}/?screen=dashboard`, { waitUntil: 'domcontentloaded', timeout: 90000 });
    await page.waitForSelector('flutter-view', { state: 'attached', timeout: 120000 });
    const semantics = page.locator('flt-semantics-placeholder');
    await semantics.waitFor({ state: 'attached', timeout: 45000 });
    await semantics.evaluate(element => element.click());
    await page.getByText('Rekomendasi', { exact: true }).waitFor({ timeout: 30000 });
    await page.waitForFunction(() => document.body.innerText.includes('Cuaca hari ini') || document.body.innerText.includes('Cuaca belum tersedia'), null, { timeout: 30000 });
    return { context, page, errors, layoutErrors, requestCounts };
  } catch (error) {
    await page.screenshot({ path: path.join(__dirname, `${mode}-failure.png`) }).catch(() => {});
    throw error;
  }
}

(async () => {
  const browser = await chromium.launch({ channel: 'msedge', headless: true });
  const telemetry = {
    recommendations: 0,
    weather: 0,
    goBaseMismatches: [],
    blockedSupabasePaths: [],
    unexpectedGoPaths: [],
  };
  const contexts = [];
  const report = {
    checkedAt: new Date().toISOString(),
    previewUrl: base,
    goApi: `${goApi.origin}${goPath}`,
    fixtureNotice: 'Supabase auth/profile/history and Go weather/recommendations are locally intercepted. No production auth, boat, trip, or recommendation writes are made.',
    checks: {},
  };
  try {
    const normal = await makeDashboard(browser, 'normal', telemetry);
    contexts.push(normal.context);
    await normal.page.screenshot({ path: path.join(__dirname, 'weather-430.png') });
    let text = await normal.page.locator('body').innerText();
    for (const [name, pattern] of Object.entries(metricPatterns)) {
      assert.match(text, pattern, `dashboard should show the ${name} fixture`);
    }
    for (const value of ['Cerah', 'Open-Meteo', 'DWD']) {
      assert.ok(text.includes(value), `dashboard should show ${value}`);
    }
    assert.ok(!text.includes('Cuaca belum tersedia'), 'fresh weather should not show an unavailable message');
    report.checks.weatherFixtureShown = true;
    report.normalWeatherText = text;
    report.errors = normal.errors;
    await normal.page.setViewportSize({ width: 360, height: 640 });
    for (const [name, pattern] of Object.entries(metricPatterns)) {
      const metric = normal.page.getByText(pattern);
      await metric.scrollIntoViewIfNeeded();
      assert.ok(await metric.isVisible(), `weather ${name} must remain visible at 360x640`);
    }
    // Wheel below the map so the map gesture handler cannot consume the scroll.
    await normal.page.mouse.move(350, 515);
    await normal.page.mouse.wheel(0, 360);
    await normal.page.waitForTimeout(250);
    for (const [name, pattern] of [
      ...Object.entries(metricPatterns),
      ['Open-Meteo attribution', /Open-Meteo/],
      ['DWD attribution', /DWD/],
    ]) {
      const element = normal.page.getByText(pattern);
      assert.ok(await element.isVisible(), `${name} must be visible at 360x640`);
      const box = await element.boundingBox();
      assert.ok(box && box.y + box.height < 560, `${name} must clear the fixed bottom navigation at 360x640`);
    }
    const pageWidth = await normal.page.evaluate(() => ({
      width: document.documentElement.clientWidth,
      scrollWidth: document.documentElement.scrollWidth,
    }));
    assert.ok(pageWidth.scrollWidth <= pageWidth.width, `360px dashboard must not overflow horizontally: ${JSON.stringify(pageWidth)}`);
    await normal.page.screenshot({ path: path.join(__dirname, 'weather-360x640.png') });
    report.checks.compactViewportWeatherAndAttributionVisible = true;
    report.compactViewport = pageWidth;

    const missingMarine = await makeDashboard(browser, 'missing-marine', telemetry);
    contexts.push(missingMarine.context);
    text = await missingMarine.page.locator('body').innerText();
    assert.match(text, metricPatterns.temperature, 'known temperature must remain visible when marine data is null');
    assert.match(text, metricPatterns.wind, 'known wind must remain visible when marine data is null');
    assert.ok(text.includes('—'), 'unknown wave height must render as an em dash');
    assert.ok(!text.includes('0 m'), 'unknown wave height must not be represented as zero');
    await missingMarine.page.screenshot({ path: path.join(__dirname, 'weather-null-marine-430.png') });
    report.checks.nullMarineRemainsUnknown = true;

    const unavailable = await makeDashboard(browser, 'unavailable', telemetry);
    contexts.push(unavailable.context);
    text = await unavailable.page.locator('body').innerText();
    assert.ok(text.includes('Cuaca belum tersedia'), 'failed weather refresh must report unavailable weather');
    for (const [name, pattern] of Object.entries(metricPatterns)) {
      assert.ok(!pattern.test(text), `weather 503 view must not keep stale ${name}`);
    }
    await unavailable.page.screenshot({ path: path.join(__dirname, 'weather-unavailable-430.png') });
    report.checks.weatherUnavailableHasNoStaleNumbers = true;

    for (const dashboard of [normal, missingMarine, unavailable]) {
      assert.ok(dashboard.requestCounts.weather > 0, 'each isolated dashboard should call the configured weather endpoint');
      assert.ok(dashboard.requestCounts.recommendations > 0, 'each isolated dashboard should exercise the recommendations 503 fixture');
    }
    assert.deepEqual(telemetry.goBaseMismatches, [], 'the app must call the exact configured Go API base');
    assert.deepEqual(telemetry.blockedSupabasePaths, [], 'no unhandled or mutating Supabase endpoint should be reached');
    assert.deepEqual(telemetry.unexpectedGoPaths, [], 'only weather and recommendations may be requested from Go');
    assert.ok(contexts.every((_, index) => [normal.errors, missingMarine.errors, unavailable.errors][index].length === 0), 'browser console should have no uncaught page errors');
    assert.ok([normal, missingMarine, unavailable].every(dashboard => dashboard.layoutErrors.length === 0), 'browser console should have no layout overflow errors');
    report.telemetry = telemetry;
    fs.writeFileSync(path.join(__dirname, 'verification.json'), JSON.stringify(report, null, 2));
    fs.rmSync(path.join(__dirname, 'failure.json'), { force: true });
    console.log(JSON.stringify(report));
  } catch (error) {
    report.failure = error.message;
    report.telemetry = telemetry;
    fs.writeFileSync(path.join(__dirname, 'failure.json'), JSON.stringify(report, null, 2));
    throw error;
  } finally {
    await Promise.all(contexts.map(context => context.close()));
    await browser.close();
  }
})().catch(error => {
  console.error(error.message);
  process.exitCode = 1;
});
