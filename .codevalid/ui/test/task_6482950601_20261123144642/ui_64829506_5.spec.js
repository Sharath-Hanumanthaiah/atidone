import { test, expect, signIn } from '../../helpers/codevalid-test.js';

test('Interface stays usable while changes are saving', async ({ page }) => {
  test.setTimeout(60000);
  // Given: a signed-in user with one open todo
  const user = { id: 650000 + Math.floor(Math.random() * 89999), login: 'cv-busy-user' };
  await signIn(page, user);
  const stamp = Date.now();
  const existing = `Pay electricity bill ${stamp}`;
  expect((await page.request.post('/api/todos', { data: { title: existing, completed: 0 } })).ok()).toBe(true);

  // Saves are held so every action below happens while earlier saves are still in flight
  let release;
  const gate = new Promise((r) => { release = r; });
  let held = 0;
  await page.route('**/api/todos**', async (route) => {
    if (['POST', 'PATCH'].includes(route.request().method())) {
      held += 1;
      await gate;
    }
    return route.fallback();
  });

  await page.goto('/optimistic-todos');
  const input = page.getByRole('textbox', { name: 'Make a Nuxt demo' });
  const existingRow = page.getByRole('listitem').filter({ hasText: existing });
  await expect(existingRow).toBeVisible();

  // When: add a todo, then right away mark the other one done, then right away add another
  const first = `Draft agenda ${stamp}`;
  const second = `Send invites ${stamp}`;
  await input.fill(first);
  await input.press('Enter');
  await expect(page.getByRole('listitem').filter({ hasText: first })).toBeVisible();
  await expect(input).toBeEnabled();
  await expect(input).toHaveValue('');

  await existingRow.getByRole('switch').click();
  await expect(existingRow.getByText(existing)).toHaveClass(/line-through/);

  await expect(input).toBeEditable();
  await input.fill(second);
  await input.press('Enter');

  // Then: every action is already in the list while the saves are still pending
  await expect(page.getByRole('listitem').filter({ hasText: second })).toBeVisible();
  await expect(page.getByRole('listitem').filter({ hasText: first })).toBeVisible();
  await expect(existingRow.getByText(existing)).toHaveClass(/line-through/);
  expect(held).toBe(3);
  // No blocking overlay or frozen controls: the input still takes text and nothing is marked busy
  await expect(input).toBeEditable();
  await expect(page.locator('[aria-busy="true"]')).toHaveCount(0);
  await expect(page.getByRole('dialog')).toHaveCount(0);

  // And after the saves and the refresh complete, the list keeps all three changes
  const refreshed = page.waitForResponse((r) => r.url().endsWith('/api/todos') && r.request().method() === 'GET');
  release();
  expect((await refreshed).ok()).toBe(true);
  await expect(page.getByRole('listitem')).toHaveCount(3);
  await expect(page.getByRole('listitem').filter({ hasText: first })).toBeVisible();
  await expect(page.getByRole('listitem').filter({ hasText: second })).toBeVisible();
  await expect(existingRow.getByText(existing)).toHaveClass(/line-through/);

  console.log('CODEVALID_TEST_ASSERTION_OK:ui_64829506_5');
});
