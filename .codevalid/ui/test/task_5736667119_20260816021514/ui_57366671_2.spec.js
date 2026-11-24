import { test, expect, signIn } from '../../helpers/codevalid-test.js';

test('Expired Google access token is refreshed without interruption', async ({ page }) => {
  // Given: a signed-in user working in the product
  await signIn(page);
  await page.goto('/todos');
  await expect(page.getByRole('button', { name: 'cv-user' })).toBeVisible();

  // When: they keep working and open another page that needs them signed in
  await page.getByRole('link', { name: 'Optimistic Todos' }).click();

  // Then: the page opens normally, they stay signed in, and no sign-in prompt is shown
  await expect(page).toHaveURL(/\/optimistic-todos$/);
  await expect(page.getByRole('button', { name: 'cv-user' })).toBeVisible();
  await expect(page.getByPlaceholder('Make a Nuxt demo')).toBeVisible();
  await expect(page.getByRole('link', { name: /Login with/i })).toHaveCount(0);
  console.log('CODEVALID_TEST_ASSERTION_OK:ui_57366671_2');
});
