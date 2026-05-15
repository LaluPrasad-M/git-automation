---
name: review-a11y
description: Accessibility (a11y) review rules for React components. Use when reviewing code for accessibility issues, auditing components for screen reader support, or ensuring keyboard navigation works correctly.
---

# Accessibility Review

## Overview

Rules for catching common accessibility violations in React components. These patterns align with WCAG 2.1 AA and the eslint-plugin-jsx-a11y ruleset.

## Key Principles

- Prefer semantic HTML over ARIA — use `<button>`, `<nav>`, `<main>` instead of `<div role="button">`
- Every interactive element must be keyboard accessible
- Every form input must have a label
- Images must have alt text (or `alt=""` for decorative images)

## Review Rules

### Images Without Alt Text

Flag `<img>`, `<area>`, `<input type="image">` without `alt` attributes.

```tsx
// ❌ Don't
<img src={logo} />

// ✅ Do
<img src={logo} alt="Company logo" />

// ✅ Do — decorative image
<img src={divider} alt="" />
```

### Click Handlers on Non-Interactive Elements

Flag `onClick` on `<div>`, `<span>`, or other non-interactive elements without keyboard support and a role.

```tsx
// ❌ Don't
<div onClick={handleClick}>Click me</div>

// ✅ Do — use a button
<button onClick={handleClick}>Click me</button>

// ✅ Do — if a div is truly needed
<div
  role="button"
  tabIndex={0}
  onClick={handleClick}
  onKeyDown={(e) => {
    if (e.key === "Enter" || e.key === " ") handleClick();
  }}
>
  Click me
</div>
```

### Missing Form Labels

Flag `<input>`, `<select>`, `<textarea>` without an associated label.

```tsx
// ❌ Don't
<input type="email" placeholder="Email" />

// ✅ Do — explicit label
<label htmlFor="email">Email</label>
<input id="email" type="email" />

// ✅ Do — aria-label for icon-only inputs
<input type="search" aria-label="Search" />
```

### Positive tabIndex

Flag `tabIndex` values greater than 0. This disrupts the natural tab order.

```tsx
// ❌ Don't
<button tabIndex={5}>Submit</button>

// ✅ Do — use 0 to add to natural tab order
<button tabIndex={0}>Submit</button>
```

### Mouse Events Without Keyboard Equivalents

Flag `onMouseOver`/`onMouseOut`/`onMouseEnter`/`onMouseLeave` without corresponding `onFocus`/`onBlur`.

```tsx
// ❌ Don't
<div onMouseEnter={showTooltip} onMouseLeave={hideTooltip}>
  Hover me
</div>

// ✅ Do
<div
  onMouseEnter={showTooltip}
  onMouseLeave={hideTooltip}
  onFocus={showTooltip}
  onBlur={hideTooltip}
  tabIndex={0}
>
  Hover me
</div>
```

### Redundant ARIA Roles

Flag ARIA roles that duplicate the element's implicit role.

```tsx
// ❌ Don't — button already has role="button"
<button role="button">Submit</button>

// ❌ Don't — nav already has role="navigation"
<nav role="navigation">...</nav>

// ✅ Do — semantic HTML is sufficient
<button>Submit</button>
<nav>...</nav>
```

### aria-hidden on Focusable Elements

Flag `aria-hidden="true"` on elements that are focusable.

```tsx
// ❌ Don't — hidden from screen readers but still focusable
<button aria-hidden="true">Close</button>

// ✅ Do — if hiding from screen readers, also remove from tab order
<button aria-hidden="true" tabIndex={-1}>Close</button>

// ✅ Do — or just make it accessible
<button aria-label="Close dialog">
  <XIcon aria-hidden="true" />
</button>
```

### Prefer Semantic HTML Over ARIA

Flag ARIA roles when a semantic HTML element exists.

```tsx
// ❌ Don't
<div role="heading" aria-level={2}>Section Title</div>
<div role="list"><div role="listitem">Item</div></div>
<span role="link" onClick={navigate}>Go</span>

// ✅ Do
<h2>Section Title</h2>
<ul><li>Item</li></ul>
<a href="/page">Go</a>
```

### Ambiguous Link Text

Flag anchor elements with non-descriptive text.

```tsx
// ❌ Don't
<a href="/docs">Click here</a>
<a href="/docs">Read more</a>

// ✅ Do
<a href="/docs">View documentation</a>
```

### autoFocus Usage

Flag `autoFocus` prop — it disrupts screen reader navigation and can be disorienting.

```tsx
// ❌ Don't — avoid in most cases
<input autoFocus />

// ✅ Do — manage focus programmatically when needed
const inputRef = useRef<HTMLInputElement>(null);
useEffect(() => {
  if (shouldFocus) inputRef.current?.focus();
}, [shouldFocus]);
```

## References

- WCAG 2.1 AA: https://www.w3.org/WAI/WCAG21/quickref/
- eslint-plugin-jsx-a11y: https://github.com/jsx-eslint/eslint-plugin-jsx-a11y
- Component structure: `./react-component-structure.md`
