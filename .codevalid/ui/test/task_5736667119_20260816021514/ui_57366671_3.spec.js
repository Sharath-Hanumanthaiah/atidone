import { test, expect, signIn } from '../../helpers/codevalid-test.js';

test('User signs out explicitly within the 30-day window', async ({ page }) => {
  test.setTimeout(60000);
  // Given: a signed-in user on a signed-in page
  await signIn(page);
  await page.goto('/todos');
  await page.waitForLoadState('networkidle');
  const userMenu = page.getByRole('button', { name: 'cv-user' });
  await expect(userMenu).toBeVisible();

  // When: they choose Logout from the user menu
  const logout = page.getByRole('menuitem', { name: 'Logout' });
  await expect(async () => {
    if (!(await logout.isVisible())) await userMenu.click();
    await expect(logout).toBeVisible({ timeout: 1000 });
  }).toPass({ timeout: 15000 });
  await logout.click();

  // Then: right away the user is shown as signed out
  await expect(page.getByRole('link', { name: 'Login with GitHub' })).toBeVisible();
  await expect(page.getByRole('button', { name: 'cv-user' })).toHaveCount(0);

  // And: opening a signed-in page shows the sign-in page instead of the content
  await page.goto('/todos');
  await expect(page).toHaveURL(/\/$/);
  await expect(page.getByRole('link', { name: 'Login with GitHub' })).toBeVisible();
  await expect(page.getByPlaceholder('Make a Nuxt demo')).toHaveCount(0);
  console.log('CODEVALID_TEST_ASSERTION_OK:ui_57366671_3');
});
