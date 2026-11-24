import { test, expect, signIn, signOut } from '../../helpers/codevalid-test.js';

test('Users see only their own todos', async ({ page }) => {
  test.setTimeout(60000);
  const base = 660000 + Math.floor(Math.random() * 40000);
  const userA = { id: base, login: 'cv-user-a' };
  const userB = { id: base + 45000, login: 'cv-user-b' };
  const stamp = Date.now();
  const titleA = `User A private todo ${stamp}`;
  const titleB = `User B own todo ${stamp}`;

  // Given: user B already has a todo of their own (so B's list is visibly loaded later)
  await signIn(page, userB);
  expect((await page.request.post('/api/todos', { data: { title: titleB, completed: 0 } })).ok()).toBe(true);
  await signOut(page);

  // User A signs in and adds a todo through the page
  await signIn(page, userA);
  await page.goto('/optimistic-todos');
  const input = page.getByRole('textbox', { name: 'Make a Nuxt demo' });
  const saved = page.waitForResponse((r) => r.url().endsWith('/api/todos') && r.request().method() === 'POST');
  await input.fill(titleA);
  await input.press('Enter');
  expect((await saved).ok()).toBe(true);
  await expect(page.getByRole('listitem').filter({ hasText: titleA })).toBeVisible();

  // When: A signs out, B signs in and opens the todo list
  await signOut(page);
  await signIn(page, userB);
  await page.goto('/optimistic-todos');

  // Then: B sees their own todo and not A's
  await expect(page.getByRole('button', { name: 'cv-user-b' })).toBeVisible();
  await expect(page.getByRole('listitem').filter({ hasText: titleB })).toBeVisible();
  await expect(page.getByRole('listitem').filter({ hasText: titleA })).toHaveCount(0);
  await expect(page.getByRole('listitem')).toHaveCount(1);

  console.log('CODEVALID_TEST_ASSERTION_OK:ui_64829506_6');
});
