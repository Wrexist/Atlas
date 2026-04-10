# Peptide-ai: Claude Code Setup Guide

## Quick Start

```bash
# Open Claude Code in this repo
claude

# Verify setup loaded correctly
/help          # Should show custom skills
/agents        # Should show security-reviewer, code-reviewer, test-writer
```

---

## Plugin Installation

### Essential Plugins (Install These First)

Open Claude Code and run `/plugin`, go to **Discover** tab, and install each:

| # | Plugin | What It Does | Priority |
|---|--------|-------------|----------|
| 1 | **superpowers** | 20+ skills: TDD, debugging, brainstorming, plan-to-code | Must have |
| 2 | **context7** | Live documentation lookup. Prevents hallucinated APIs. | Must have |
| 3 | **code-review** | Structured code reviews with built-in reviewer agent | Must have |
| 4 | **security-guidance** | OWASP Top 10 scanning, injection detection, secret scanning | Must have |
| 5 | **commit-commands** | Git workflow: smart commits, PR creation, changelog | Must have |
| 6 | **frontend-design** | Polished UI generation (400k+ installs, most popular plugin) | Must have |

### High-Value Plugins

| # | Plugin | What It Does |
|---|--------|-------------|
| 7 | **feature-dev** | End-to-end feature workflow: spec -> plan -> implement -> test -> PR |
| 8 | **hookify** | Create hooks conversationally (easier than editing JSON) |
| 9 | **plugin-dev** | 7 expert skills for building your own plugins |
| 10 | **ralph-wiggum** | Autonomous coding sessions with clean git history |

### Integration Plugins (Add Based on Need)

| Plugin | When to Install |
|--------|----------------|
| **github** | Working with PRs, issues, CI/CD |
| **playwright** | Browser testing, UI automation |
| **chrome-devtools** | Frontend debugging with live Chrome |
| **sentry** | Production error monitoring |
| **vercel** | Deploying to Vercel |
| **supabase** | Using Supabase for backend |
| **stripe** | Payment integration |
| **linear** | Issue tracking with Linear |
| **slack** | Team communication integration |

### Language Server Plugins (Install for Your Language)

| Plugin | Language |
|--------|----------|
| **typescript-lsp** | TypeScript / JavaScript |
| **pyright-lsp** | Python |
| **rust-analyzer-lsp** | Rust |
| **gopls-lsp** | Go |
| **ruby-lsp** | Ruby |
| **jdtls-lsp** | Java |
| **kotlin-lsp** | Kotlin |
| **csharp-lsp** | C# |
| **swift-lsp** | Swift |

### Knowledge Work Plugins (Optional)

Add the marketplace first:
```
/plugin marketplace add anthropics/knowledge-work-plugins
```

Then install from Discover tab:
- **brand-voice** - Consistent brand tone
- **marketing** - SEO, content strategy
- **sales** - Prospect research, email sequences
- **legal** - Contract review, compliance
- **finance** - Financial analysis, budgets
- **productivity** - Meeting summaries, task management

---

## Opus 4.6 Performance Optimization

### Effort Levels

| Command | When to Use |
|---------|------------|
| `/effort max` | Architecture decisions, complex debugging, system design |
| `/effort high` | Default. Standard implementation work. |
| `/effort medium` | Routine changes, small refactors |
| `/effort low` | Linting fixes, simple renames, formatting |
| `/effort auto` | Reset to model default |

Trigger one-off deep reasoning by including **"ultrathink"** in your prompt.

### Speed vs Quality

| Mode | Command | Use Case |
|------|---------|----------|
| **Normal** | (default) | Standard development work |
| **Fast** | `/fast` | Rapid iteration, quick fixes, live debugging (2.5x faster) |
| **OpusPlan** | `/model opusplan` | Plan with Opus, execute with Sonnet (saves tokens) |

### Context Management

- **`/clear`** between unrelated tasks. The single most impactful habit.
- **Subagents** for investigation. Keeps your main context clean.
- **`/compact`** when context is getting large. Add focus: `/compact Focus on API changes`
- **`/btw`** for quick questions that don't need to stay in context.
- **`/rewind`** (or `Esc + Esc`) to restore previous state if something goes wrong.

### Session Management

```bash
claude --continue        # Resume last session
claude --resume          # Pick from recent sessions
/rename oauth-migration  # Name sessions for easy finding
```

### Plugin Token Budget

More plugins = more context overhead. The sweet spot is **3-5 active plugins**.

```
/plugin disable <name>   # Disable plugins you're not using
/plugin enable <name>    # Re-enable when needed
/plugin                  # Browse and manage plugins
```

---

## Custom Skills (Built-in)

These skills are pre-configured in `.claude/skills/`:

| Skill | Command | Description |
|-------|---------|-------------|
| Explore Codebase | `/explore-codebase <question>` | Structured exploration using subagents |
| Fix Issue | `/fix-issue <number>` | End-to-end issue resolution |
| Deep Debug | `/deep-debug <description>` | Systematic debugging with hypothesis testing |
| New Feature | `/new-feature <description>` | Feature implementation workflow |

## Custom Agents (Built-in)

Pre-configured in `.claude/agents/`:

| Agent | Model | Purpose |
|-------|-------|---------|
| security-reviewer | Opus | OWASP Top 10, injection, auth, secrets review |
| code-reviewer | Sonnet | Code quality, patterns, edge cases, performance |
| test-writer | Sonnet | Comprehensive test generation |

Use them: `"Use a security-reviewer subagent to review the auth module"`

## Safety Hooks (Active)

These run automatically via `.claude/settings.json`:

- **Block dangerous commands**: `rm -rf /`, `git push --force main`, `DROP TABLE`, etc.
- **Protect sensitive files**: Blocks writes to `.env`, `.pem`, `.key`, `credentials.json`

To create new hooks conversationally, install the **hookify** plugin.

---

## Resources

- [Claude Code Docs](https://code.claude.com/docs)
- [Plugin Marketplace](https://claude.com/plugins)
- [Official Plugins Repo](https://github.com/anthropics/claude-plugins-official)
- [Best Practices](https://code.claude.com/docs/en/best-practices)
- [Model Configuration](https://code.claude.com/docs/en/model-config)
- [What's New in Claude 4.6](https://platform.claude.com/docs/en/about-claude/models/whats-new-claude-4-6)
