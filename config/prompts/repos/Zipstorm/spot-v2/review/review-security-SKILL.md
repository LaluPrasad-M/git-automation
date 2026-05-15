---
name: review-security
description: Security review rules for React frontend code. Use when reviewing code for XSS vulnerabilities, secret leaks, injection risks, or unsafe browser API usage.
---

# Security Review

## Overview

Rules for catching common security vulnerabilities in React frontend code. Covers XSS, secret exposure, injection vectors, and unsafe browser API patterns.

## Key Principles

- Never trust user input — validate and sanitize at the boundary
- Secrets do not belong in client-side code
- `dangerouslySetInnerHTML` is a red flag that requires manual review every time
- Prefer framework-provided escaping over manual sanitization

## Review Rules

### dangerouslySetInnerHTML

Flag ALL uses. If the value comes from user input, it must be sanitized with DOMPurify or equivalent.

```tsx
// ❌ Don't — unsanitized user content
<div dangerouslySetInnerHTML={{ __html: userComment }} />

// ⚠️ Requires review — even sanitized usage needs justification
import DOMPurify from "dompurify";
<div dangerouslySetInnerHTML={{ __html: DOMPurify.sanitize(userComment) }} />

// ✅ Do — render text safely
<div>{userComment}</div>
```

### Sensitive Data in Storage

Flag `localStorage` or `sessionStorage` storing tokens, secrets, or credentials. These are accessible to any JS on the page (including XSS payloads).

```tsx
// ❌ Don't
localStorage.setItem("authToken", token);
sessionStorage.setItem("jwt", response.jwt);

// ✅ Do — use httpOnly cookies set by the server
// Token is stored server-side in a secure, httpOnly cookie
```

### API Keys and Secrets in Client Code

Flag string literals that look like API keys (`sk_`, `pk_`, `AKIA`, long hex/base64 strings) and environment variables not prefixed for client exposure.

```tsx
// ❌ Don't — secret in client bundle
const API_KEY = "sk_live_abc123def456";
const secret = process.env.DATABASE_URL;

// ✅ Do — use client-safe env vars, proxy secrets through your API
const apiUrl = import.meta.env.VITE_API_URL;
```

### javascript: Protocol in href

Flag `href="javascript:..."` — this is an XSS vector.

```tsx
// ❌ Don't
<a href="javascript:void(0)">Click</a>
<a href={`javascript:${userInput}`}>Link</a>

// ✅ Do
<button onClick={handleClick}>Click</button>
<a href="/safe-path">Link</a>
```

### User-Controlled href Without Validation

Flag dynamic `href` values from user input or URL parameters without validation.

```tsx
// ❌ Don't — user could inject javascript: protocol
<a href={userProvidedUrl}>Visit</a>

// ✅ Do — validate the URL
function isSafeUrl(url: string): boolean {
  try {
    const parsed = new URL(url);
    return ["http:", "https:"].includes(parsed.protocol);
  } catch {
    return false;
  }
}

{isSafeUrl(userProvidedUrl) && <a href={userProvidedUrl}>Visit</a>}
```

### eval() and Dynamic Code Execution

Flag `eval()`, `new Function()`, and `setTimeout`/`setInterval` with string arguments.

```tsx
// ❌ Don't
eval(userInput);
new Function("return " + expression)();
setTimeout("alert('hi')", 1000);

// ✅ Do
const result = safeParser(expression);
setTimeout(() => alert("hi"), 1000);
```

### Console Logging Sensitive Data

Flag `console.log` calls that reference auth tokens, passwords, user PII, or API responses containing sensitive data. Also flag stray `console.log` in production code paths.

```tsx
// ❌ Don't
console.log("Token:", authToken);
console.log("User:", { email, password, ssn });

// ✅ Do — log only non-sensitive identifiers
console.log("Auth succeeded for userId:", userId);
```

### CSS Injection via User Input

Flag dynamic style props constructed from unsanitized user input.

```tsx
// ❌ Don't — user could inject CSS expressions or break layout
<div style={{ background: userInput }} />
<div style={{ width: `${userInput}px` }} />

// ✅ Do — validate/constrain the value
const safeWidth = Math.min(Math.max(Number(userInput), 0), 100);
<div style={{ width: `${safeWidth}px` }} />
```

### Unvalidated Redirects

Flag `window.location`, `window.open`, or router navigation using unsanitized user input.

```tsx
// ❌ Don't
window.location.href = searchParams.get("redirect")!;

// ✅ Do — validate against an allowlist
const redirect = searchParams.get("redirect");
const allowedPaths = ["/dashboard", "/settings", "/profile"];
if (redirect && allowedPaths.includes(redirect)) {
  navigate(redirect);
}
```

### PostMessage Without Origin Check

Flag `window.addEventListener("message", ...)` handlers that don't verify `event.origin`.

```tsx
// ❌ Don't — accepts messages from any origin
window.addEventListener("message", (event) => {
  processData(event.data);
});

// ✅ Do — verify origin
window.addEventListener("message", (event) => {
  if (event.origin !== "https://trusted-domain.com") return;
  processData(event.data);
});
```

## References

- OWASP Top 10: https://owasp.org/www-project-top-ten/
- React security docs: https://react.dev/reference/react-dom/components/common#dangerously-setting-the-inner-html
