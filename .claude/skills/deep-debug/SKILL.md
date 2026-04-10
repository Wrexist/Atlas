---
name: deep-debug
description: Systematic debugging workflow. Reproduces the issue, isolates root cause, implements fix, and verifies. Use for hard-to-find bugs.
effort: max
---

# Deep Debug

Debug the issue: $ARGUMENTS

## Workflow

1. **Reproduce** - Run the failing scenario. Capture the exact error, stack trace, and conditions.
2. **Gather context** - Use subagents to:
   - Read relevant source files
   - Check recent git history for related changes (`git log --oneline -20 -- <file>`)
   - Search for similar patterns or known issues
3. **Form hypotheses** - List 2-3 possible root causes ranked by likelihood.
4. **Isolate** - For each hypothesis:
   - Add targeted logging or assertions
   - Run minimal reproduction
   - Confirm or eliminate the hypothesis
5. **Root cause** - Document the exact root cause with:
   - Which file and line
   - Why it fails
   - Under what conditions
6. **Fix** - Implement the minimal fix. Explain why this fix addresses the root cause.
7. **Verify** - Run the reproduction scenario again. Confirm the fix resolves it.
8. **Regression test** - Write a test that catches this specific bug pattern.

## Rules
- Don't guess. Reproduce first, then investigate.
- Use git blame and git log to understand why code was written a certain way before changing it.
- Fix the root cause, not the symptom. Don't add try/catch around broken logic.
- If stuck after 3 hypotheses, widen the investigation scope or ask for help.
