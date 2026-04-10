---
name: new-feature
description: Structured feature implementation workflow. Goes from spec to plan to implementation to tests to PR. Use for non-trivial new features.
disable-model-invocation: true
---

# New Feature

Implement the feature: $ARGUMENTS

## Workflow

1. **Spec** - Clarify requirements:
   - What exactly should this feature do?
   - What are the inputs and outputs?
   - What are the edge cases?
   - Are there existing patterns to follow?
   Use the AskUserQuestion tool if requirements are ambiguous.

2. **Explore** - Use subagents to investigate:
   - Similar features already in the codebase (follow their patterns)
   - Dependencies and utilities that can be reused
   - Files that will need to be modified

3. **Plan** - Write a brief implementation plan:
   - List files to create/modify
   - Describe the approach
   - Note potential risks or tradeoffs

4. **Implement** - Build the feature incrementally:
   - Start with core logic
   - Add error handling at boundaries
   - Follow existing patterns and conventions
   - Don't over-engineer. Build what's needed now.

5. **Test** - Write comprehensive tests:
   - Happy path
   - Edge cases
   - Error scenarios
   - Integration with existing features

6. **Review** - Self-review the diff:
   - Use a code-reviewer subagent for an independent check
   - Fix any issues found

7. **Ship** - Commit with a descriptive message and create a PR.

## Rules
- Follow existing patterns in the codebase. Don't introduce new paradigms.
- Keep PRs focused. If the feature is large, break it into smaller PRs.
- Every public function/endpoint needs tests.
- Run the full test suite before creating the PR.
