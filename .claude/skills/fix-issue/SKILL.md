---
name: fix-issue
description: End-to-end GitHub issue resolution workflow. Reads the issue, finds relevant code, implements the fix, writes tests, and creates a PR.
disable-model-invocation: true
---

# Fix Issue

Fix the GitHub issue: $ARGUMENTS

## Workflow

1. **Read the issue** - Use `gh issue view` or MCP tools to get full issue details including comments
2. **Understand the problem** - Identify the bug/feature from the issue description. Note reproduction steps if available.
3. **Find relevant code** - Use subagents to search the codebase for files related to the issue. Look at:
   - Files mentioned in the issue
   - Error messages or stack traces
   - Related components and dependencies
4. **Plan the fix** - Before coding, outline what needs to change and why. Consider edge cases.
5. **Implement the fix** - Make minimal, focused changes. Don't refactor unrelated code.
6. **Write tests** - Add tests that:
   - Reproduce the original bug (should fail without the fix)
   - Verify the fix works
   - Cover edge cases mentioned in the issue
7. **Verify** - Run the test suite. Ensure all tests pass, including existing ones.
8. **Commit and PR** - Create a descriptive commit referencing the issue number. Push and create a PR.

## Rules
- Keep changes minimal and focused on the issue.
- Always reference the issue number in commits: `fix: resolve #<number> - <description>`
- Run tests before creating the PR.
- If the issue is unclear, ask for clarification before implementing.
