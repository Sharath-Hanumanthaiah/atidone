import { test, expect, signIn } from '../../helpers/codevalid-test.js';

test('List stays in sync with the server after a change', async ({ page }) => {
  test.setTimeout(60000);
  // Given: a signed-in user with one existing todo
  const user = { id: 640000 + Math.floor(Math.random() * 89999), login: 'cv-sync-user' };
  await signIn(page, user);
  const stamp = Date.now();
  const existing = `Book dentist ${stamp}`;
  expect((await page.request.post('/api/todos', { data: { title: existing, completed: 0 } })).ok()).toBe(true);

  await page.goto('/optimistic-todos');
  const items = page.getByRole('listitem');
  await expect(items.filter({ hasText: existing })).toBeVisible();

  // When: the user adds a todo and the background refresh finishes
  const title = `Water the plants ${stamp}`;
  const saved = page.waitForResponse((r) => r.url().endsWith('/api/todos') && r.request().method() === 'POST');
  const refreshed = page.waitForResponse((r) => r.url().endsWith('/api/todos') && r.request().method() === 'GET');
  const input = page.getByRole('textbox', { name: 'Make a Nuxt demo' });
  await input.fill(title);
  await input.press('Enter');
  expect((await saved).ok()).toBe(true);
  expect((await refreshed).ok()).toBe(true);
  await expect(items).toHaveCount(2);
  await expect(items.filter({ hasText: title })).toBeVisible();
  const afterRefresh = await items.allInnerTexts();

  // And the page is reloaded
  await page.reload();

  // Then: the reloaded list matches what the background refresh showed, including the new todo
  await expect(items).toHaveCount(2);
  await expect(items.filter({ hasText: title })).toBeVisible();
  await expect(items).toHaveText(afterRefresh);

  console.log('CODEVALID_TEST_ASSERTION_OK:ui_64829506_4');
});
