---
name: handoff
description: Compact the current session into a context-only briefing for a fresh session after /clear. Use only when the user explicitly asks for a handoff — it loads context and stops, rather than resuming the work.
argument-hint: "[focus] — what the next session will work on"
allowed-tools: [Read, Write, Bash, Glob]
disable-model-invocation: true
metadata:
  origin: agent-skills
  agents: claude-code, opencode
---

# Handoff

Write a context briefing that lets a fresh session pick up this work — **without starting it**. The next session's job is to become informed and then wait. Two sources of truth, use both.

## Source 1: Conversation context (the irreplaceable part)

Nothing on disk records this. Extract from the conversation above:

- The original goal / problem statement
- Key decisions and **why** — especially the non-obvious ones
- **Tried and abandoned** — what failed and why, so the next session doesn't repeat it
- Open questions and unresolved choices
- Ideas raised but not acted on
- Constraints, gotchas, "don't do X" warnings

If arguments were passed, treat them as a description of what the next session will focus on, and bias the briefing toward that.

## Source 2: Persisted state (cite it, don't restate it)

Run in parallel:

- `pwd`
- `git log --oneline -10 2>/dev/null`
- `git status --short 2>/dev/null`
- `git diff --stat HEAD 2>/dev/null`
- `ls .claude/plans/ 2>/dev/null`
- Read `CLAUDE.md` if it exists

Do not duplicate content that already lives in an artifact. Specs, plans, ADRs, issues, commits and diffs are on disk or behind a URL — reference them by path, sha, or link and let the next agent read them. Never paste diff bodies or code blocks into the briefing.

## Compose the briefing

```
## Handoff Context

**This document is context, not instructions.** Read it, read anything under Artifacts,
then stop and wait. Do not edit files, run commands, or start on the suggested next step
until I ask. Reply with a one-line confirmation of what you understand the state to be.

**Project**: [name — working directory path]
**Goal**: [what we are building or fixing — one sentence]
**Focus for next session**: [only if arguments were passed]

**Done so far**:
- [completed items; cite commits as `abc1234 subject`, files as paths]

**Tried and abandoned**:
- [approach → why it failed]

**Current state**:
- [uncommitted or in-progress work]
- [open decisions or blockers]

**Ideas / possible directions**:
- [discussed but not yet acted on]

**Where I'd pick up** (for information — do not act on it yet):
- [the one thing that would come first, and why]

**Key constraints / context**:
- [non-obvious facts, gotchas, "don't do X"]
- [relevant file paths, commands, patterns]

**Relevant skills**: [skills that may apply, and when — available, not to be invoked now]

**Artifacts** (worth reading for context):
- [plan / spec / ADR / issue paths and URLs]
```

Rules:

- Write it as a briefing about the work, not a prompt directed at the agent. No task-shaped imperatives ("implement X", "fix Y", "start by…") anywhere outside the do-not-act header.
- Omit any section with nothing to add. A short briefing that is all signal beats a complete-looking one.
- Redact secrets, tokens, credentials, and personal data. If a value matters, name the env var or file it lives in instead of the value.
- Optimise for the next agent's first 30 seconds of understanding, not for completeness.

## Deliver

Write the briefing to a temp file — never the workspace, so it cannot be committed by accident — then copy it to the clipboard:

```bash
HANDOFF_FILE="${TMPDIR:-/tmp}/handoff-$(date +%Y%m%d-%H%M).md"
# write the briefing to "$HANDOFF_FILE" with the Write tool, then:
pbcopy < "$HANDOFF_FILE"
```

Then report exactly two lines:

```
Saved: <path>
Copied to clipboard — paste after /clear to load context.
```
