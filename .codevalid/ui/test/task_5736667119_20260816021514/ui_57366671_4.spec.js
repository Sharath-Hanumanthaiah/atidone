import { test, expect, signIn } from '../../helpers/codevalid-test.js';

/**
 * Simulate closing the browser and coming back `days` later: a browser drops session cookies
 * (no expiry) on restart, and any cookie whose expiry falls before the return date. Only clears
 * cookies the app set; never writes one.
 */
async function closeAndReturnAfter(page, days) {
  await page.goto('about:blank');
  const context = page.context();
  const returnAt = Date.now() / 1000 + days * 24 * 60 * 60;
  for (const c of await context.cookies()) {
    if (c.expires <= 0 || c.expires < returnAt) {
      await context.clearCookies({ name: c.name, domain: c.domain, path: c.path });
    }
  }
}

test('Returning after 30 days requires signing in again', async ({ page }) => {
  test.setTimeout(60000);
  // Given: the user signed in and the app shows them signed in
  await signIn(page);
  await page.goto('/todos');
  await expect(page.getByRole('button', { name: 'cv-user' })).toBeVisible();

  // When: they close the product and return after more than 30 days, opening a signed-in page
  await closeAndReturnAfter(page, 31);
  await page.goto('/todos');

  // Then: they are shown as signed out and get the sign-in page
  await expect(page).toHaveURL(/\/$/);
  const login = page.getByRole('link', { name: 'Login with GitHub' });
  await expect(login).toBeVisible();
  await expect(page.getByRole('button', { name: 'cv-user' })).toHaveCount(0);

  // When: they sign in again through the (mock) provider
  await login.click();

  // Then: the requested content is shown
  await expect(page).toHaveURL(/\/todos$/);
  await expect(page.getByRole('button', { name: 'cv-user' })).toBeVisible();
  await expect(page.getByPlaceholder('Make a Nuxt demo')).toBeVisible();
  console.log('CODEVALID_TEST_ASSERTION_OK:ui_57366671_4');
});
