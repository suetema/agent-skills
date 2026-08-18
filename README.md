# agent-skills

My agent skills, kept in one place and installed into both **Claude Code** and **opencode**.

One `SKILL.md` per skill is the single source of truth. `install.sh` symlinks it into each
agent's load path, so editing the file in this repo takes effect in both immediately —
no copying, no drift.

```
skills/<name>/SKILL.md      skills I maintain, shared by both harnesses
external-skills.txt         skills I want but don't maintain — linked, never copied
opencode/command/<name>.md  thin wrapper so /<name> shows in opencode's prompter
install.sh                  symlinks all of it into place
```

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

### Maintained here

| Skill | What it does |
|---|---|
| [`handoff`](skills/handoff/SKILL.md) | Compacts the session into a context-only briefing for a fresh session after `/clear`. The next agent reads it and **stops** — it does not resume the work. |

### Linked from elsewhere

Tracked in [`external-skills.txt`](external-skills.txt). This repo records *which* skills I
want installed; the upstream repo keeps the content.

| Skill | Source | Harnesses | Notes |
|---|---|---|---|
| `market-research` | affaan-m/ECC | both | Market sizing, competitor comparison, investor dossiers. No external dependencies. |
| `deep-research` | affaan-m/ECC | both | Cited multi-source reports. **Requires firecrawl + exa MCPs** — without them the skill describes tool calls it cannot make. |
| 11 engineering skills | affaan-m/ECC | opencode | `tdd-workflow`, `security-review`, `coding-standards`, `frontend-patterns`, `frontend-slides`, `backend-patterns`, `e2e-testing`, `verification-loop`, `api-design`, `strategic-compact`, `eval-harness` |

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

## opencode: getting a skill into the `/` prompter

opencode loads skills fine, but lists skill-sourced entries only under its `/skills`
picker — they do not appear in the `/` autocomplete when you type. Verified against the
local server API (`opencode serve` + `GET /command`), where the skill shows up as
`{"name": "handoff", "source": "skill"}`.

The fix is a same-named command in `opencode/command/<name>.md`. A command with the same
name as a skill **overrides** the entry rather than duplicating it — one result, with
`source` flipped from `skill` to `command`, which is what the prompter lists:

```markdown
---
description: Compact this session into a context-only briefing for a fresh session
---

Invoke the `handoff` skill and follow it exactly.

Focus for the next session (may be empty): $ARGUMENTS
```

The wrapper stays deliberately thin — it defers to the skill instead of restating it, so
`SKILL.md` remains the single source of truth. `$ARGUMENTS` is parsed by opencode and
passed through.

Claude Code needs no equivalent: user-invocable skills already appear in its `/` menu.

### Consequence of the permission guard

Because the wrapper asks the model to invoke the skill, `permission.skill.handoff: "ask"`
(above) will prompt for approval even when you triggered `/handoff` yourself. If that
friction outweighs the protection, set it to `"allow"` — the skill's `description` still
carries "use only when the user explicitly asks", which is all opencode gives you.

## Tracking skills you don't maintain

`external-skills.txt` is a manifest, not a vendor directory — no content is copied, so there
is no fork to keep in sync and no license question. `install.sh` symlinks each entry into both
harnesses; `git pull` in the upstream repo is what updates them.

```
# <name>  <path>  [targets]        ~ expands to $HOME, trailing # comments ignored
market-research  ~/src/ECC/skills/market-research  both
tdd-workflow     ~/src/ECC/skills/tdd-workflow     opencode
```

The `<name>` column is the installed name, so `/<name>` is what you type. It does not have to
match the upstream directory — rename on the way in if two sources collide.

`targets` is `both` (default), `claude`, `opencode`, or `claude,opencode`. Per-harness scope
matters when a name is already taken: ECC's `security-review` would shadow Claude Code's
bundled skill of the same name, so it stays opencode-only.

**The manifest is authoritative.** Narrow an entry's targets and the next run prunes its link
from the harness it no longer names, reporting `pruned <path> (no longer targeted)`. Nothing
outside this repo decides what is installed.

If a source repo isn't cloned on this machine, install.sh prints `MISSING <name> -> <path>`,
counts it as skipped, and creates no broken link. Exit status stays 0, so a partial checkout
doesn't fail the install. `--uninstall` removes external links too: it matches on the link
target, which keeps working even if the upstream checkout is gone.

Prompter visibility works the same as for local skills — add `opencode/command/<name>.md`
that defers to the skill. Nothing about being external changes that.

### Migrating ECC's opencode skills into this repo (2026-08-18)

The 11 engineering skills used to be listed as absolute paths in `skills.paths` inside
`~/.config/opencode/opencode.json`, which put install decisions in a machine-local file this
repo could not see. They now live in `external-skills.txt`, and the `skills` key is gone from
`opencode.json`.

The effective set was verified unchanged across the move — 15 skills before and after, same
names — by diffing `GET /skill` from a local `opencode serve` on each side. opencode dedupes
skills by name, so the intermediate state where a skill was both listed and linked resolved to
one entry rather than a conflict.

If a future ECC install writes `skills.paths` back into `opencode.json`, the same names will
resolve through whichever source loads them first. Prefer removing the config entries and
letting the manifest own it.

### Conflict with ECC's own installer

ECC has a first-class selective installer (`./install.sh --skills a,b`, `--profile`,
`--modules`, `--with/--without`, `--config ecc-install.json`, `--dry-run`). It is *not*
compatible with the links this repo makes, and it says so loudly:

```
Error: Refusing to install Claude skill through symlinked Claude skill path:
'/Users/<me>/.claude/skills/deep-research'
```

That refusal is the desired behaviour — it will not write through a symlink and corrupt the
upstream checkout. But it means one skill name belongs to one mechanism. To hand a skill back
to ECC's installer, drop its line from `external-skills.txt` and re-run `./install.sh` first.

Why symlinks anyway: ECC's skill selection is module-granular, not file-granular. A dry-run of
`--skills deep-research,market-research` plans **17 file operations** — both skills plus
`exa-search`, `research-ops`, `documentation-lookup`, five `scientific-*` skills, and platform
scaffolding (`plugin.json`, `marketplace.json`, `mcp-servers.json`, `auto-update.js`). For
comparison: `--profile research` is 678 operations, `--profile full` is 1004. Two symlinks are
two files. ECC sanctions this — its README states each component is fully independent and
documents manual copying.

Use ECC's installer when you want what symlinks cannot express: hooks, rules, agents, or
managed uninstall via its install-state tracking.

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
2. For opencode prompter visibility, add `opencode/command/<name>.md` that says
   "Invoke the `<name>` skill and follow it exactly."
3. `./install.sh`, then restart opencode (it discovers at startup).
4. Commit. Other machines get it with `git pull` + `./install.sh` for new skills;
   edits to existing files need no re-install.
