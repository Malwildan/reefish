const { chromium } = require(process.env.PLAYWRIGHT_MODULE || 'playwright');

const baseUrl = process.env.PREVIEW_URL || 'http://127.0.0.1:4194';

async function main() {
  const browser = await chromium.launch({ channel: 'msedge', headless: true });
  try {
    const page = await browser.newPage({ viewport: { width: 430, height: 932 } });
    const authRequests = [];

    await page.route('**/auth/v1/token**', async (route) => {
      const request = route.request();
      authRequests.push({ method: request.method(), pathname: new URL(request.url()).pathname });
      await route.fulfill({
        status: 400,
        contentType: 'application/json',
        body: JSON.stringify({
          code: 400,
          error_code: 'invalid_credentials',
          msg: 'Invalid login credentials',
        }),
      });
    });

    await page.goto(`${baseUrl}/?screen=login`, { waitUntil: 'domcontentloaded' });
    await page.waitForSelector('flutter-view, flt-glass-pane', {
      state: 'attached',
      timeout: 120000,
    });
    const accessibilityToggle = page.locator('flt-semantics-placeholder');
    await page.waitForTimeout(5000);
    if (await accessibilityToggle.count()) {
      await accessibilityToggle.evaluate((element) => element.click());
    }
    await page.waitForFunction(
      () => document.querySelector('flt-semantics-host')?.innerText.includes('Nomor Telepon'),
      null,
      { timeout: 120000 },
    );

    const inputs = page.locator('input');
    await inputs.nth(0).fill('81234567890');
    await inputs.nth(1).fill('Local-Test-Password-123');
    const submit = page.getByRole('button', { name: 'Masuk', exact: true });
    await submit.click();
    await page.waitForFunction(() => {
      const host = document.querySelector('flt-semantics-host');
      return host?.innerText.includes('Nomor ponsel atau kata sandi tidak sesuai.');
    }, null, { timeout: 15000 }).catch(() => {});

    const renderedText = await page.locator('flt-semantics-host').innerText();
    const unconfiguredMessageVisible = renderedText.includes('belum terhubung');
    if (authRequests.length !== 1 || authRequests[0].pathname !== '/auth/v1/token') {
      throw new Error(`Expected one intercepted Supabase token request; observed ${authRequests.length}.`);
    }
    if (unconfiguredMessageVisible) {
      throw new Error('The UI still shows the unconfigured account-service message.');
    }
    const invalidCredentialsMessageVisible = renderedText.includes(
      'Nomor ponsel atau kata sandi tidak sesuai.',
    );
    if (!invalidCredentialsMessageVisible) {
      throw new Error('The intercepted invalid-credentials response was not shown in the UI.');
    }

    console.log(JSON.stringify({
      pageLoaded: true,
      sdkRequest: `${authRequests[0].method} ${authRequests[0].pathname}`,
      requestIntercepted: true,
      unconfiguredMessageVisible,
      uiError: 'Nomor ponsel atau kata sandi tidak sesuai.',
      credentialsPrinted: false,
    }, null, 2));
  } finally {
    await browser.close();
  }
}

main().catch((error) => {
  console.error(error.message);
  process.exitCode = 1;
});
