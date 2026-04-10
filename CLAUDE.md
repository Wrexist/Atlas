# Peptide-ai

## Project Overview
AI-powered project (direction TBD). This file configures Claude Code for maximum Opus 4.6 performance.

## Code Standards
- Write clean, minimal code. No premature abstractions.
- Prefer composition over inheritance.
- Functions should do one thing. If a function needs a comment explaining what it does, split it.
- No unused imports, variables, or dead code. Delete, don't comment out.
- Error handling at system boundaries only (user input, external APIs, file I/O). Trust internal code.
- IMPORTANT: Never commit secrets, API keys, or credentials. Use environment variables.

## Git Workflow
- Branch naming: `feature/<name>`, `fix/<name>`, `refactor/<name>`
- Commit messages: imperative mood, under 72 chars, explain WHY not WHAT
- One logical change per commit. Don't mix refactoring with feature work.
- IMPORTANT: Never force-push to main/master without explicit permission.
- Run tests before committing. Don't commit broken code.

## Testing
- Write tests for business logic and edge cases, not trivial getters/setters.
- Test behavior, not implementation. Tests should survive refactoring.
- Prefer integration tests over unit tests for API endpoints.
- Use descriptive test names: `test_<scenario>_<expected_behavior>`

## Context Management (Opus 4.6)
- YOU MUST use subagents for codebase investigation to preserve main context.
- Use /clear between unrelated tasks. Don't let context accumulate.
- Scope explorations narrowly. Never read every file in a directory.
- When investigating, report findings concisely. Don't dump raw file contents.
- For large tasks: explore -> plan -> implement -> verify. Don't skip steps.

## Installed Plugins
These plugins are available. Use them appropriately:
- **superpowers**: TDD, debugging, brainstorming skills. Use for structured workflows.
- **context7**: Live documentation lookup. Use BEFORE writing code that uses external libraries.
- **code-review**: Structured reviews. Use before PRs.
- **security-guidance**: Vulnerability scanning. Runs automatically via hooks.
- **commit-commands**: Git automation. Use for commits and PRs.
- **feature-dev**: End-to-end feature workflow. Use for new features.
- **frontend-design**: UI generation. Use for any frontend work.

## Performance Tips
- Use `/effort max` for architecture decisions and complex debugging.
- Use `/effort high` (default) for implementation work.
- Use `/effort low` for linting fixes, simple renames, formatting.
- Use `/fast` when iterating rapidly on small changes.
- Use `opusplan` mode to plan with Opus and implement with Sonnet (saves tokens).
- Trigger deep reasoning with "ultrathink" in prompts for one-off complex turns.

## File Structure
```
.claude/
  settings.json    - Hooks (safety guards)
  skills/          - Reusable workflows (/explore-codebase, /fix-issue, /deep-debug, /new-feature)
  agents/          - Specialized subagents (security-reviewer, code-reviewer, test-writer)
```
