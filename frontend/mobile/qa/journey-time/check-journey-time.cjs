const { chromium } = require('playwright');
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');

const base = process.env.PREVIEW_URL || 'http://127.0.0.1:4195';
const owner = '11111111-1111-4111-8111-111111111111';
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
const token = `${encode({ alg: 'HS256', typ: 'JWT' })}.${encode({ sub: owner, exp: expires, role: 'authenticated' })}.local-test-signature`;
const session = {
  access_token: token,
  refresh_token: 'local-fixture-refresh',
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
  home_port: { lat: -8.433, lng: 112.683 },
  is_default: true,
};

(async () => {
  const browser = await chromium.launch({ channel: 'msedge', headless: true });
  let page;
  try {
    const context = await browser.newContext({
      viewport: { width: 430, height: 932 },
      permissions: ['geolocation'],
      geolocation: { latitude: -8.433, longitude: 112.683 },
    });
    await context.addInitScript(({ fixtureSession }) => {
      if (!localStorage.getItem('journey-time-qa-initialized')) {
        localStorage.setItem('sb-upyahsecuorqghcghflg-auth-token', JSON.stringify(fixtureSession));
        localStorage.setItem('journey-time-qa-initialized', '1');
      }
    }, { fixtureSession: session });

    page = await context.newPage();
    const errors = [];
    const layoutErrors = [];
    const submissions = [];
    let boatCreated = false;
    let tripCreated = false;
    page.on('pageerror', error => errors.push(error.message));
    page.on('console', message => {
      if (/overflowed|EXCEPTION CAUGHT BY RENDERING|RenderFlex/i.test(message.text())) {
        layoutErrors.push(message.text());
      }
    });

    const profile = () => ({
      id: owner,
      name: 'Nelayan QA',
      phone: '6280000000000',
      role: 'nelayan',
      onboarded: tripCreated,
      next_step: !boatCreated ? 'boat' : tripCreated ? 'done' : 'first_trip',
      boat: boatCreated ? boat : null,
      stats: { trip_count: tripCreated ? 1 : 0, baseline_fuel_liters: tripCreated ? 12 : null, baseline_catch_kg: tripCreated ? 14 : null },
    });

    await page.route('**/*.supabase.co/**', async route => {
      const url = new URL(route.request().url());
      const json = (body, status = 200) => route.fulfill({ status, contentType: 'application/json', body: JSON.stringify(body) });
      if (url.pathname === '/auth/v1/user') return json(user);
      if (url.pathname === '/auth/v1/token') return json(session);
      if (url.pathname === '/auth/v1/logout') return json({});
      const name = url.pathname.split('/').pop();
      if (name === 'get_grid_lock_snapshot') {
        return json({ version: 'journey-time-fixture', fetched_at: new Date(Date.now() - 1000).toISOString(), expires_at: new Date(Date.now() + 300000).toISOString(), is_demo: false, locks: [] });
      }
      if (name === 'api_me') return json(profile());
      if (name === 'api_create_boat') {
        const body = route.request().postDataJSON();
        assert.equal(body.p.engine_hp, 15);
        assert.equal(body.p.boat_length_m, 7);
        boatCreated = true;
        return json(boat);
      }
      if (name === 'api_post_trip') {
        const body = route.request().postDataJSON();
        submissions.push(body.p);
        tripCreated = true;
        return json({
          trip: {
            id: '33333333-3333-4333-8333-333333333333',
            source: body.p.source,
            fuel_liters: body.p.fuel_liters,
            catch_kg: body.p.catch_kg,
            departed_at: body.p.departed_at,
            returned_at: body.p.returned_at,
          },
          user: { onboarded: true },
          replay: false,
          recommendations: null,
        });
      }
      if (name === 'api_list_trips') {
        return json({
          data: tripCreated ? [{ id: '33333333-3333-4333-8333-333333333333', source: 'onboarding', departed_at: submissions[0].departed_at, fuel_liters: 12, catch_kg: 14 }] : [],
          meta: { page: 1, limit: 5, total: tripCreated ? 1 : 0 },
          summary: { trip_count: tripCreated ? 1 : 0, total_catch_kg: tripCreated ? 14 : 0, total_fuel_liters: tripCreated ? 12 : 0 },
        });
      }
      return json({ code: 'PGRST202', message: 'Fixture blocks unhandled API' }, 404);
    });

    const enable = async () => {
      await page.waitForSelector('flutter-view', { state: 'attached', timeout: 120000 });
      const toggle = page.locator('flt-semantics-placeholder');
      await toggle.waitFor({ state: 'attached', timeout: 45000 });
      await toggle.evaluate(element => element.click());
    };
    const button = name => page.getByRole('button', { name, exact: true });
    const typeField = async (index, value) => {
      const field = page.locator('input').nth(index);
      await field.click();
      await field.press('ControlOrMeta+A');
      await field.pressSequentially(value, { delay: 40 });
      await page.waitForTimeout(120);
      assert.equal(await field.inputValue(), value, `field ${index} should retain typed value`);
    };
    const shot = async name => {
      await page.waitForTimeout(400);
      await page.screenshot({ path: path.join(__dirname, `${name}.png`) });
    };

    // Enter the existing onboarding flow; the map selection is backed by browser geolocation.
    await page.goto(`${base}/?screen=departure`, { waitUntil: 'domcontentloaded', timeout: 90000 });
    await enable();
    await button('Pilih Lokasi Saat Ini').click();
    await button('Edit').waitFor();
    await page.waitForTimeout(300);
    await button('Simpan').click();
    await page.getByText('Tempatkan titik ikan?', { exact: true }).waitFor();
    await page.waitForTimeout(400);
    await page.mouse.click(260, 230);
    await page.waitForTimeout(400);
    await button('Selesai').click();
    await page.getByText('Kekuatan mesin', { exact: true }).waitFor({ timeout: 30000 });
    const boatInputs = page.locator('input');
    await boatInputs.nth(0).fill('Kapal QA');
    await boatInputs.nth(1).fill('15');
    await boatInputs.nth(2).fill('7');
    await button('Lanjutkan').click();
    await page.getByText('Catat Perjalanan Melaut', { exact: true }).waitFor();

    const fields = page.locator('input');
    assert.equal(await fields.count(), 6, 'journey form should expose six numeric inputs');
    // Flutter synchronizes a semantics input's DOM value on focus.
    const initial = [];
    for (let index = 0; index < 6; index++) {
      await fields.nth(index).click();
      await page.waitForTimeout(120);
      initial.push(await fields.nth(index).inputValue());
    }
    assert.deepEqual(initial, ['', '', '', '00', '', '00'], 'hour inputs should start blank and minute inputs should default to 00');
    assert.equal(await fields.nth(2).getAttribute('placeholder'), 'JJ', 'departure hour hint should be JJ');
    assert.equal(await fields.nth(4).getAttribute('placeholder'), 'JJ', 'return hour hint should be JJ');
    await shot('journey-time-initial');

    // Prove validation runs before any trip request when a default minute is cleared.
    await fields.nth(3).click();
    await fields.nth(3).press('ControlOrMeta+A');
    await fields.nth(3).press('Backspace');
    await page.waitForTimeout(120);
    assert.equal(await fields.nth(3).inputValue(), '');
    await typeField(0, '12');
    await typeField(1, '14');
    await typeField(2, '00');
    await typeField(4, '01');
    await button('Lanjutkan').click();
    await page.waitForTimeout(400);
    assert.equal(submissions.length, 0, 'incomplete time must not call api_post_trip');
    const minuteError = page.getByText('Menit berangkat wajib diisi (00–59).', { exact: true });
    await minuteError.waitFor({ state: 'visible' });
    await shot('journey-time-validation');

    // Restore the minute default, leaving both minute values as 00 for the real submission.
    await typeField(3, '00');
    await minuteError.waitFor({ state: 'hidden' });
    assert.equal(await fields.nth(3).inputValue(), '00');
    // The untouched return minute is verified from the submitted payload.
    await button('Lanjutkan').click();
    await page.getByText('Rekomendasi', { exact: true }).waitFor({ timeout: 30000 });
    assert.equal(submissions.length, 1);
    assert.equal(submissions[0].source, 'onboarding');
    assert.equal(submissions[0].fuel_liters, 12);
    assert.equal(submissions[0].catch_kg, 14);
    const departedMs = Date.parse(submissions[0].departed_at);
    const returnedMs = Date.parse(submissions[0].returned_at);
    assert.ok(Number.isFinite(departedMs) && Number.isFinite(returnedMs), 'submitted timestamps should be valid ISO timestamps');
    assert.equal(new Date(departedMs).getUTCMinutes(), 0, 'departure payload minute should remain 00');
    assert.equal(new Date(returnedMs).getUTCMinutes(), 0, 'return payload minute should remain 00');
    assert.equal(returnedMs - departedMs, 60 * 60 * 1000, 'submitted 00 and 01 hours should remain one hour apart');
    await shot('journey-time-submitted');
    assert.deepEqual(errors, []);
    assert.deepEqual(layoutErrors, []);

    const report = {
      checkedAt: new Date().toISOString(),
      previewUrl: base,
      checks: {
        journeyFormInitialHoursBlank: true,
        minuteDefaultsAre00: true,
        hourHintsAreJJ: true,
        clearingMinuteRejectedWithoutApiCall: true,
        restoringDefaultMinuteAllowsSubmission: true,
        submittedTimestampsPreserve00MinutesAndOneHourGap: true,
      },
      initialInputs: initial,
      finalPayload: {
        fuel_liters: submissions[0].fuel_liters,
        catch_kg: submissions[0].catch_kg,
        departed_at: submissions[0].departed_at,
        returned_at: submissions[0].returned_at,
      },
      submissions: submissions.length,
      errors,
      layoutErrors,
      fixtureNotice: 'Auth, boat, trip, and grid policy HTTP responses were intercepted locally. No production credentials or trip writes were used.',
      nativeAndroid: 'not tested',
    };
    fs.writeFileSync(path.join(__dirname, 'verification.json'), JSON.stringify(report, null, 2));
    console.log(JSON.stringify(report));
  } catch (error) {
    if (page) {
      await page.screenshot({ path: path.join(__dirname, 'failure.png') });
      fs.writeFileSync(path.join(__dirname, 'failure.txt'), await page.locator('body').innerText());
    }
    throw error;
  } finally {
    await browser.close();
  }
})().catch(error => {
  console.error(error);
  process.exitCode = 1;
});
