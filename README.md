# agent-skills

My agent skills, kept in one place and installed into both **Claude Code** and **opencode**.

One `SKILL.md` per skill is the single source of truth. `install.sh` symlinks it into each
agent's load path, so editing the file in this repo takes effect in both immediately —
no copying, no drift.

## Install

```bash
git clone https://github.com/suetema/agent-skills.git ~/src/agent-skills
cd ~/src/agent-skills && ./install.sh
```

Then reload: `/reload-skills` in Claude Code; opencode picks up skills on next start.

```bash
./install.sh              # link everything (idempotent)
./install.sh --force      # move a pre-existing real directory aside as .bak
./install.sh --uninstall  # remove only links that point into this repo
```

## Skills

| Skill | What it does |
|---|---|
| [`handoff`](skills/handoff/SKILL.md) | Compacts the session into a context-only briefing for a fresh session after `/clear`. The next agent reads it and **stops** — it does not resume the work. |

## Why two symlinks

opencode's docs claim it reads `~/.claude/skills`. On **opencode 1.18.12 it does not.**
Verified with `opencode debug skill` against probe skills planted in every candidate path:

| Path | opencode 1.18.12 |
|---|---|
| `~/.config/opencode/skills/<name>/SKILL.md` | loaded |
| `~/.agents/skills/<name>/SKILL.md` | loaded |
| `<project>/.opencode/skills/`, `<project>/.agents/skills/` | loaded |
| `skills.paths` entries in `opencode.json` | loaded |
| `~/.claude/skills/<name>/SKILL.md` | **not loaded** |
| `<project>/.claude/skills/` | **not loaded** |

Symlinked skill directories are followed, so one file can serve both trees.
Re-check with `opencode debug skill` after an opencode upgrade — if `~/.claude/skills`
starts working, the second link becomes redundant (harmless either way).

## Frontmatter compatibility

Both agents read the same file. opencode recognizes only `name`, `description`, `license`,
`compatibility`, and `metadata`, and **silently ignores** everything else — so the
Claude-Code-specific fields are inert there rather than an error.

| Field | Claude Code | opencode |
|---|---|---|
| `name`, `description` | honored | honored |
| `metadata` (string→string) | ignored | honored |
| `argument-hint` | honored | ignored |
| `allowed-tools` | honored | ignored |
| `disable-model-invocation` | honored | **ignored** — see below |

### Keeping skills explicit-invocation-only in opencode

`disable-model-invocation: true` stops Claude Code from firing a skill on its own.
opencode has no equivalent field; use per-skill permission in `~/.config/opencode/opencode.json`:

```json
{
  "permission": {
    "skill": { "handoff": "ask" }
  }
}
```

`deny` would block your own explicit invocation too, so `ask` is the closer analogue.
The skill's `description` also carries the constraint in prose, which is what a model
actually reads when deciding whether to invoke.

## Portability decisions

Deliberate constraints, so a later edit doesn't quietly break one harness:

- **No shell injection in skill bodies.** Claude Code can run `` !`cmd` `` (and ```` ```! ```` blocks)
  before the body reaches the model, which would make the `handoff` skill's git-state gathering
  deterministic instead of instructed. opencode has no documented equivalent, so those lines would
  most likely reach the model as literal text. Skill bodies stay as instructions the model follows.
- **No `${CLAUDE_SKILL_DIR}` / `${CLAUDE_*}` substitutions**, for the same reason. If a skill ever
  needs a bundled script, reference it by a path the model can resolve itself.
- **Claude-Code-only frontmatter is fine.** `argument-hint`, `allowed-tools`, and
  `disable-model-invocation` are silently ignored by opencode rather than rejected, so they cost
  nothing. Behavioural guarantees they provide must be restated for opencode — see the permission
  section above.

If a skill ever genuinely needs a harness-specific feature, fork it into two files and say so here
rather than degrading it in one harness by accident.

## Adding a skill

1. `mkdir -p skills/<name>` and write `SKILL.md` with at minimum `name` + `description`.
2. `./install.sh`
3. Commit. Other machines get it with `git pull` — no re-install unless the skill is new.
