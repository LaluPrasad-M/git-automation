---
name: review-testing
description: Testing anti-pattern review rules for Vitest Browser Mode component tests. Use when reviewing test code for query misuse, async mistakes, implementation detail testing, or testing library best practices.
---

# Testing Anti-Patterns Review

## Overview

Rules for catching common testing mistakes in React component tests using Vitest Browser Mode. Focuses on query selection, async handling, and testing behavior over implementation.

## Key Principles

- Query by accessibility role first, test IDs last
- Use the right query variant for the assertion type
- Test user-visible behavior, not component internals
- Handle async correctly — use `expect.element()` for auto-retrying assertions

## Review Rules

### getByTestId When Semantic Query Exists

Flag `getByTestId` or `queryByTestId` when the element has an accessible role, label, or text. Test IDs are a last resort.

```tsx
// Don't — button has an accessible name
page.getByTestId("submit-btn")

// Do — query by role and accessible name
page.getByRole("button", { name: /submit/i })

// Don't — input has a label
page.getByTestId("email-input")

// Do
page.getByLabelText(/email/i)
```

**Query priority order:**
1. `page.getByRole` — accessible role + name
2. `page.getByLabelText` — form inputs
3. `page.getByPlaceholder` — when no label exists
4. `page.getByText` — non-interactive text
5. `page.getByDisplayValue` — filled form elements
6. `page.getByAltText` — images
7. `page.getByTitle` — title attribute
8. `page.getByTestId` — last resort only

### Missing `expect.element()` for DOM Assertions

Flag `expect(page.getByRole(...)).toBeInTheDocument()` without `expect.element()`. In Vitest Browser Mode, `expect.element()` auto-retries until the element appears.

```tsx
// Don't — no auto-retry, may fail on async renders
expect(page.getByText("Loaded")).toBeInTheDocument()

// Do — auto-retries until element appears
await expect.element(page.getByText("Loaded")).toBeInTheDocument()
```

### Using `screen` Instead of `page`

Flag `screen.getByRole(...)` or `screen.getByText(...)`. This project uses Vitest Browser Mode where queries come from `page` (imported from `vitest/browser`), not `screen`.

```tsx
// Don't — Testing Library API
screen.getByRole("button", { name: /submit/i })

// Do — Vitest Browser Mode API
page.getByRole("button", { name: /submit/i })
```

### fireEvent Instead of userEvent or `.click()`

Flag `fireEvent.click`, `fireEvent.change`, `fireEvent.type`. In Vitest Browser Mode, use `userEvent` from `vitest/browser` or the element's `.click()` method.

```tsx
// Don't — doesn't simulate full interaction
fireEvent.change(input, { target: { value: "hello" } })
fireEvent.click(button)

// Do — simulates real user behavior
await userEvent.fill(input, "hello")
await page.getByRole("button", { name: /submit/i }).click()
```

### Testing Implementation Details

Flag tests that assert on internal state, instance methods, component internals, CSS class names, or hook return values directly. Test what the user sees.

```tsx
// Don't — testing internal state
expect(component.state.isOpen).toBe(true)

// Don't — testing CSS classes
expect(button).toHaveClass("btn-primary-active")

// Don't — testing hook internals
const { result } = renderHook(() => useCounter())
expect(result.current.internalState).toBe(0)

// Do — test visible behavior
await page.getByRole("button", { name: /open/i }).click()
await expect.element(page.getByRole("dialog")).toBeVisible()
```

### Redundant act() Wrapping

Flag `act()` wrapping `render()` or interaction calls. In Vitest Browser Mode, these are handled automatically.

```tsx
// Don't — render already handles this
await act(async () => {
  render(<MyComponent />)
})

// Do
render(<MyComponent />)
```

### Missing jest-dom Matchers

Flag generic matchers when domain-specific matchers exist. Better matchers give clearer failure messages.

```tsx
// Don't
expect(button.disabled).toBe(true)
expect(input.value).toBe("hello")

// Do
expect(button).toBeDisabled()
expect(input).toHaveValue("hello")
```

### Missing Async Handling

Flag tests that trigger state updates or async operations without `await` or `expect.element()`.

```tsx
// Don't — state update isn't awaited
test("loads user", () => {
  render(<UserProfile />)
  expect(page.getByText("John")).toBeInTheDocument()
})

// Do
test("loads user", async () => {
  render(<UserProfile />)
  await expect.element(page.getByText("John")).toBeInTheDocument()
})
```

### Snapshot Overuse

Flag large snapshot tests that capture entire component trees. These break on any change and provide little signal about what actually matters.

```tsx
// Don't — brittle, hard to review
expect(container).toMatchSnapshot()

// Do — assert on specific behavior
await expect.element(page.getByRole("heading")).toHaveTextContent("Welcome")
await expect.element(page.getByRole("button", { name: /submit/i })).toBeEnabled()
```

## References

- Vitest component testing: `./vitest-component-testing.md`
- Testing requirements: `./testing-requirements.md`
- Common mistakes with Testing Library: https://kentcdodds.com/blog/common-mistakes-with-react-testing-library
