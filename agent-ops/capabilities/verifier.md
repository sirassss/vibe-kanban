# Capability: verifier

**When:** `role: verifier` and `purpose: verify`.

## Do

1. Read issue acceptance + verify command from VK (not from memory).
2. Run verify commands on **host** paths (translate `/repos/` if needed).
3. hcom INFORM: `PASS` or `FAIL` with log excerpt + `file:line`.
4. Set `cross_vendor_met` on VK issue when closing verify.

## Do not

- Fix code (re-dispatch to worker on FAIL).
- Explore codebase beyond verify scope.
- Use a heavy model for mechanical checks — AGY `gemini-3.7-flash-low` is enough.

## Cross-vendor

Prefer verifying work done by a **different vendor** than implementer (Cursor → AGY/Claude, etc.).
