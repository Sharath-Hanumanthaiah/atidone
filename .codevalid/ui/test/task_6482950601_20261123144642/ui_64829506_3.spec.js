import { test, expect, signIn } from '../../helpers/codevalid-test.js';

test('Delete a todo and see it disappear instantly', async ({ page }) => {
  test.setTimeout(60000);
  // Given: a signed-in user whose list contains a todo to delete and one to keep
  const user = { id: 630000 + Math.floor(Math.random() * 89999), login: 'cv-delete-user' };
  await signIn(page, user);
  const stamp = Date.now();
  const doomed = `Cancel gym membership ${stamp}`;
  const kept = `Renew passport ${stamp}`;
  expect((await page.request.post('/api/todos', { data: { title: doomed, completed: 0 } })).ok()).toBe(true);
  expect((await page.request.post('/api/todos', { data: { title: kept, completed: 0 } })).ok()).toBe(true);

  // Hold the delete request until the optimistic removal has been checked
  let release;
  const gate = new Promise((r) => { release = r; });
  await page.route('**/api/todos/*', async (route) => {
    if (route.request().method() === 'DELETE') await gate;
    return route.fallback();
  });

  await page.goto('/optimistic-todos');
  const doomedRow = page.getByRole('listitem').filter({ hasText: doomed });
  const keptRow = page.getByRole('listitem').filter({ hasText: kept });
  await expect(doomedRow).toBeVisible();
  await expect(keptRow).toBeVisible();

  // When: the user deletes the todo (the row's delete button; the toggle is a switch, not a button)
  await doomedRow.getByRole('button').click();

  // Then: it is gone before the server confirms
  await expect(doomedRow).toHaveCount(0);
  await expect(keptRow).toBeVisible();

  // And it does not come back after the delete and the list refresh
  const deleted = page.waitForResponse((r) => /\/api\/todos\/\d+$/.test(r.url()) && r.request().method() === 'DELETE');
  const refreshed = page.waitForResponse((r) => r.url().endsWith('/api/todos') && r.request().method() === 'GET');
  release();
  expect((await deleted).ok()).toBe(true);
  expect((await refreshed).ok()).toBe(true);
  await expect(doomedRow).toHaveCount(0);
  await expect(keptRow).toBeVisible();

  console.log('CODEVALID_TEST_ASSERTION_OK:ui_64829506_3');
});
