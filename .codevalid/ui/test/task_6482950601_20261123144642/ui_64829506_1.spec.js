import { test, expect, signIn } from '../../helpers/codevalid-test.js';

test('Add a new todo and see it in the list immediately', async ({ page }) => {
  test.setTimeout(60000);
  // Given: a fresh signed-in user (unique id so the list holds only this test's todos)
  const user = { id: 610000 + Math.floor(Math.random() * 89999), login: 'cv-add-user' };
  await signIn(page, user);

  // Hold the create request until the optimistic row has been checked (no response body, just a delay)
  let release;
  const gate = new Promise((r) => { release = r; });
  await page.route('**/api/todos', async (route) => {
    if (route.request().method() === 'POST') await gate;
    return route.fallback();
  });

  await page.goto('/optimistic-todos');
  const input = page.getByRole('textbox', { name: 'Make a Nuxt demo' });
  await expect(input).toBeVisible();

  // When: the user types a title and submits
  const title = `Write release notes ${Date.now()}`;
  await input.fill(title);
  await input.press('Enter');

  // Then: the todo is in the list while the server has not answered yet
  const row = page.getByRole('listitem').filter({ hasText: title });
  await expect(row).toHaveCount(1);
  await expect(row).toBeVisible();

  // And it is still there after the save and the background refresh finish
  const saved = page.waitForResponse((r) => r.url().endsWith('/api/todos') && r.request().method() === 'POST');
  const refreshed = page.waitForResponse((r) => r.url().endsWith('/api/todos') && r.request().method() === 'GET');
  release();
  expect((await saved).ok()).toBe(true);
  expect((await refreshed).ok()).toBe(true);
  await expect(row).toHaveCount(1);
  await expect(row).toBeVisible();
  await expect(row.getByRole('switch')).toBeEnabled();

  console.log('CODEVALID_TEST_ASSERTION_OK:ui_64829506_1');
});
