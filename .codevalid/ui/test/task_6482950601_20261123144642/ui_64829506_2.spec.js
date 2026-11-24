import { test, expect, signIn } from '../../helpers/codevalid-test.js';

test('Mark a todo as done and see it update instantly', async ({ page }) => {
  test.setTimeout(60000);
  // Given: a signed-in user whose list contains one open todo
  const user = { id: 620000 + Math.floor(Math.random() * 89999), login: 'cv-toggle-user' };
  await signIn(page, user);
  const title = `Call the plumber ${Date.now()}`;
  const created = await page.request.post('/api/todos', { data: { title, completed: 0 } });
  expect(created.ok()).toBe(true);

  // Hold the update request until the optimistic state has been checked
  let release;
  const gate = new Promise((r) => { release = r; });
  await page.route('**/api/todos/*', async (route) => {
    if (route.request().method() === 'PATCH') await gate;
    return route.fallback();
  });

  await page.goto('/optimistic-todos');
  const row = page.getByRole('listitem').filter({ hasText: title });
  const label = row.getByText(title);
  const toggle = row.getByRole('switch');
  await expect(toggle).toHaveAttribute('aria-checked', 'false');
  await expect(label).not.toHaveClass(/line-through/);

  // When: the user marks it as done
  await toggle.click();

  // Then: it is shown as done before the server confirms
  await expect(label).toHaveClass(/line-through/);
  await expect(toggle).toHaveAttribute('aria-checked', 'true');

  // And it stays done after the save and the list refresh
  const saved = page.waitForResponse((r) => /\/api\/todos\/\d+$/.test(r.url()) && r.request().method() === 'PATCH');
  const refreshed = page.waitForResponse((r) => r.url().endsWith('/api/todos') && r.request().method() === 'GET');
  release();
  expect((await saved).ok()).toBe(true);
  expect((await refreshed).ok()).toBe(true);
  await expect(label).toHaveClass(/line-through/);
  await expect(toggle).toHaveAttribute('aria-checked', 'true');

  console.log('CODEVALID_TEST_ASSERTION_OK:ui_64829506_2');
});
