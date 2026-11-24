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

test('Returning within 30 days keeps user signed in', async ({ page }) => {
  // Given: the user signed in and the app shows them signed in
  await signIn(page);
  await page.goto('/todos');
  await expect(page.getByRole('button', { name: 'cv-user' })).toBeVisible();

  // When: they close the product without signing out and return 3 days later
  await closeAndReturnAfter(page, 3);
  await page.goto('/todos');

  // Then: the signed-in page opens with the user shown as signed in, no sign-in prompt
  await expect(page).toHaveURL(/\/todos$/);
  await expect(page.getByRole('button', { name: 'cv-user' })).toBeVisible();
  await expect(page.getByRole('link', { name: 'Todos', exact: true })).toBeVisible();
  await expect(page.getByPlaceholder('Make a Nuxt demo')).toBeVisible();
  await expect(page.getByRole('link', { name: /Login with/i })).toHaveCount(0);
  console.log('CODEVALID_TEST_ASSERTION_OK:ui_57366671_1');
});
