---
name: explore-codebase
description: Structured codebase exploration that preserves main context by using subagents. Use when onboarding, investigating architecture, or understanding unfamiliar code.
---

# Explore Codebase

Explore and understand the codebase for: $ARGUMENTS

## Workflow

1. **Scope the exploration** - Identify which areas of the codebase are relevant to the query
2. **Launch subagents** - Use up to 3 parallel subagents to investigate different areas. Each subagent should:
   - Search for relevant files using Glob and Grep
   - Read key files to understand patterns
   - Report findings concisely (not raw file dumps)
3. **Synthesize findings** - Combine subagent reports into a clear summary:
   - Architecture overview (how components connect)
   - Key files and their responsibilities
   - Patterns and conventions in use
   - Dependencies and external integrations
4. **Answer the original question** with specific file paths and line references

## Rules
- ALWAYS use subagents for file reading to keep the main context clean
- Never read entire directories. Target specific files based on naming patterns.
- Report findings as structured summaries, not raw code dumps.
- Include file paths in the format `path/to/file:line_number` for easy navigation.
