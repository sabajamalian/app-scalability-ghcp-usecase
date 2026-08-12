---
applyTo: "frontend/**"
description: React rendering and payload rules for performance work.
---

# React frontend performance rules

## Payload size is a backend problem that shows up in the browser

Before optimizing a component, check what the API actually returned. In this repo every response
carries `sqlQueryCount` and `serverMillis`, and the browser network panel shows the transfer size.
A list endpoint that ships a full object graph will feel slow no matter how the component renders.
The fix is a narrower DTO on the server, not `React.memo` on the client.

## Measure a render before you optimize it

- Use the React DevTools Profiler, or `performance.now()` around the interaction, and record a
  number before and after.
- `useMemo` and `useCallback` are not free: they add allocation and a dependency array to keep
  correct. Adding them without a profile usually makes the code harder to read and no faster.
- The common real wins, in order: send less data, render fewer rows (virtualize or paginate),
  avoid re-fetching on every keystroke (debounce), and split state so a change re-renders a
  subtree rather than the page.

## Fetching

- Do not fire a request per keystroke. Debounce, and cancel superseded requests with `AbortController`.
- Never fetch in a loop over a list. That is the frontend spelling of N+1: it turns one user
  action into N round trips, and the server sees N times the load under concurrency.
- Keep the loading and error states explicit. Under load the interesting behaviour is what the UI
  does at p99, not at p50.

## This repo specifically

The frontend is a demo harness. Its job is to make the measurement visible: each scenario page
shows the server-reported query count and server time next to the wall-clock time the browser saw.
Keep that display intact when changing the UI, because the demo's whole argument rests on the
numbers being in front of the user.

The Vite dev server is used on purpose rather than a production build, so edits Copilot makes
during the demo hot-reload immediately.
