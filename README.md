# agent-skills

My agent skills and the record of which ones are installed where — **Claude Code** for work,
**opencode** for private projects.

**The two harnesses are managed separately and on purpose.** Claude Code is for work,
opencode is for private projects, so each has its own manifest and neither inherits from the
other. A skill installed in one is not installed in the other unless it is listed twice.

Nothing is ever copied. `install.sh` symlinks each entry from wherever it already lives, so
upstream repos stay the source of truth and editing a file here takes effect immediately.

```
skills/<name>/SKILL.md      skills authored here
agents/<name>.md            opencode-format agents authored here (see Agents below)
claude/skills.txt           what is installed for Claude Code   (work)
claude/agents.txt
opencode/skills.txt         what is installed for opencode      (private)
opencode/agents.txt
opencode/command/<name>.md  thin wrapper so /<name> shows in opencode's prompter
install.sh                  symlinks all of it into place
```

## Install

```bash
git clone https://github.com/suetema/agent-skills.git ~/src/agent-skills
cd ~/src/agent-skills && ./install.sh
```

Then reload: `/reload-skills` in Claude Code; restart opencode, which discovers skills,
agents and commands at startup.

```bash
./install.sh              # link everything (idempotent)
./install.sh --force      # move a pre-existing real directory aside as .bak
./install.sh --uninstall  # remove only links that point into this repo
```

## Skills

### Claude Code (work) — `claude/skills.txt`

| Skill | Source | Notes |
|---|---|---|
| `handoff` | this repo | |
| `add-skill` | this repo | |
| `tdd-workflow` | affaan-m/ECC | The one ECC engineering skill on the work side — the RED/GREEN gate is language-agnostic, though every example in it is JS/TS. Also in opencode. |

### opencode (private) — `opencode/skills.txt`

| Skill | Source | Notes |
|---|---|---|
| `handoff` | this repo | Also installed for Claude Code — listed in both manifests. |
| `add-skill` | this repo | Also in both. Encodes these conventions so a new session doesn't re-derive them. |
| `market-research` | affaan-m/ECC | Private-project tooling; deliberately not in Claude Code. |
| `deep-research` | affaan-m/ECC | **Requires firecrawl + exa MCPs** — without them the skill describes tool calls it cannot make. |
| 11 engineering skills | affaan-m/ECC | `tdd-workflow` (also on the work side), `security-review`, `coding-standards`, `frontend-patterns`, `frontend-slides`, `backend-patterns`, `e2e-testing`, `verification-loop`, `api-design`, `strategic-compact`, `eval-harness` |
| `prototype` | mattpocock/skills | Throwaway prototypes that answer a design question. Multi-file: `SKILL.md` links `LOGIC.md` and `UI.md`, so it is linked as a directory from a clone rather than copied. |

`security-review` is another reason the split matters: ECC's copy would shadow Claude Code's
bundled skill of the same name, so it stays on the opencode side only.

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

## How the manifests work

Each harness has its own pair of files, and each is the whole story for that harness:

| Manifest | Installs to |
|---|---|
| `claude/skills.txt` | `~/.claude/skills/<name>/` |
| `claude/agents.txt` | `~/.claude/agents/<name>.md` |
| `opencode/skills.txt` | `~/.config/opencode/skills/<name>/` |
| `opencode/agents.txt` | `~/.config/opencode/agent/<name>.md` (singular `agent`, unlike Claude Code) |

```
# <name>  <path>
handoff          ./skills/handoff                  # repo-relative
market-research  ~/src/ECC/skills/market-research   # anywhere on disk
```

The `<name>` column is the installed name, so `/<name>` is what you type. It need not match the
upstream directory — rename on the way in if two sources collide.

**Manifests are authoritative, not additive.** Delete a line, re-run, and the link is pruned
from that harness with `pruned <path> (not listed for <harness>)`. Pruning only touches links
this repo owns — links pointing inside the repo, or at a path some manifest mentions. A skill
you linked by hand from somewhere unlisted is left alone.

To install the same skill in both harnesses, list it in both files. To move one from work to
private, move the line and re-run — the old link is pruned in the same pass.

If a source repo isn't cloned on this machine, install.sh prints `MISSING`, counts it skipped,
and creates no broken link. Exit status stays 0, so a partial checkout doesn't fail the install.

### Agents

opencode's other agents (`architect`, `code-reviewer`, `explore`, …) come from the ECC plugin at
`~/.config/opencode/plugins/ecc-global.ts` rather than from files, so the manifests cover only
what is added here:

| Agent | Source | Why |
|---|---|---|
| `architect` | affaan-m/ECC | System design and technical trade-offs. **Shadows a plugin agent in opencode — see below.** |
| `code-explorer` | affaan-m/ECC | Traces execution paths through existing code. |
| `security-reviewer` | affaan-m/ECC | Vulnerability and secrets review. |
| `planner` | affaan-m/ECC | Implementation plans for larger changes. |

All four are installed in **both** harnesses — but not from the same file, for the reason below.
Claude Code links them straight from `~/src/ECC/agents/`; opencode gets converted copies in
`agents/`, keeping the upstream body **verbatim** and translating only the frontmatter. Two
choices in that conversion are deliberate: `write`/`edit` are pinned `false` rather than omitted
(an unlisted tool is not a denied tool, and read-only is the point of these three), and `model:`
is dropped rather than translated, so the agent inherits the session model instead of pinning an
Anthropic one. **After an ECC `git pull`, re-convert if an upstream body changed** — the copies
do not track it.

**A conversion's body IS its opencode prompt.** Anything written in it — including a provenance
comment — becomes text the model reads on every invocation. Provenance therefore lives in
`opencode/agents.txt` and here, never in the file. Verified: each converted agent's resolved
prompt is byte-identical to the upstream body.

#### `architect` shadows ECC's own opencode agent

opencode already had an `architect` before this repo added one, supplied by the ECC plugin from
its catalog at `~/src/ECC/.opencode/opencode.json`. Ours does not merge with it — it **replaces
it entirely**. Verified against a live `opencode serve`: the resolved prompt is our file's, the
plugin's is absent, and the agent count is unchanged at 33.

What changes as a result, all of it deliberate but none of it obvious:

| | ECC plugin's version | ours |
|---|---|---|
| Prompt | `.opencode/prompts/agents/architect.txt`, 4.6k | `agents/architect.md` body, 7.0k |
| Model | pinned `anthropic/claude-opus-4-5` | inherits the session model |
| Tools | `read`, `bash` | `read`, `grep`, `glob` — no `bash` |

The two prompts are genuinely different documents, not two copies of one. Un-pinning the model
is the point of the conversion recipe; losing `bash` and gaining `grep`/`glob` follows the
upstream `agents/architect.md` tool list. To hand the name back to the plugin, delete the line
from `opencode/agents.txt` and re-run `./install.sh`.

Two overlaps worth knowing rather than tripping over: `security-reviewer` is an *agent* and does
not collide with Claude Code's bundled `/security-review` *skill*, though its own closing line
points at "skill: `security-review`", which resolves to ECC's copy in opencode and to the
bundled one in Claude Code. And `planner` covers similar ground to Claude Code's built-in `Plan`.

**Agent definitions are not portable between the harnesses**, unlike skill bodies. ECC's
`agents/*.md` are Claude Code format and link into `~/.claude/agents/` as-is. Listing one for
opencode is actively dangerous: its `tools: Read, Grep, Glob` comma list yields a
`ConfigInvalidError` that invalidates opencode's **entire** config, so every agent stops
resolving. `install.sh` refuses to create such a link:

```
INVALID   opencode agents code-reviewer: 'tools:' is a Claude-Code comma list;
          opencode needs an object map.
```

It also refuses a bare `model:` alias like `sonnet`, which would pin an Anthropic model inside a
harness configured for other providers. To get the same agent in opencode, author a native one
as `agents/<name>.md` and list that — see
[`skills/add-skill/reference.md`](skills/add-skill/reference.md) for the conversion recipe.

### Migrating ECC's opencode skills into this repo (2026-08-18)

The 11 engineering skills used to be listed as absolute paths in `skills.paths` inside
`~/.config/opencode/opencode.json`, which put install decisions in a machine-local file this
repo could not see. They now live in `opencode/skills.txt`, and the `skills` key is gone from
`opencode.json`.

The effective set was verified unchanged across the move — 15 skills before and after, same
names — by diffing `GET /skill` from a local `opencode serve` on each side. opencode dedupes
skills by name, so the intermediate state where a skill was both listed and linked resolved to
one entry rather than a conflict.

No ECC adapter writes `skills.paths`, so its installer will not put those entries back — they
were hand-wired originally. ECC's native installer has in fact never run on this machine: none
of `~/.claude/ecc/install-state.json`, `~/.opencode/ecc-install-state.json`, or
`~/.config/opencode/ecc/install-state.json` exist.

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
to ECC's installer, drop its line from that harness's manifest and re-run `./install.sh` first.

**The guard is per-name, not blanket.** `scripts/lib/install/apply.js` walks every path segment
from the adapter's target root to the destination and throws if any segment is a symlink. Since
`~/.claude` and `~/.claude/skills` are real directories, only the leaf names this repo has
linked are blocked. Every other ECC skill installs alongside them without complaint.

**The opencode target does not collide at all — but can shadow.** ECC's `opencode` adapter
installs to `~/.opencode/`, not `~/.config/opencode/`, so our links sit outside its target root
and the symlink guard never sees them. However, opencode *does* read `~/.opencode/skills/` and
`~/.opencode/commands/` (verified against 1.18.12), and ECC's `opencode` profile plans 44 skills
there. Five names overlap with what this repo manages:

```
e2e-testing  eval-harness  strategic-compact  tdd-workflow  verification-loop
```

opencode dedupes skills by name, so this produces one entry per name rather than an error — but
which copy wins is load-order dependent. If you ever run ECC's opencode target, narrow those
five lines out of `opencode/skills.txt` first so ownership stays unambiguous.

Why symlinks anyway: ECC's skill selection is module-granular, not file-granular. A dry-run of
`--skills deep-research,market-research` plans **17 file operations** — both skills plus
`exa-search`, `research-ops`, `documentation-lookup`, five `scientific-*` skills, and platform
scaffolding (`plugin.json`, `marketplace.json`, `mcp-servers.json`, `auto-update.js`). For
comparison: `--profile research` is 678 operations, `--profile full` is 1004. Two symlinks are
two files. ECC sanctions this — its README states each component is fully independent and
documents manual copying.

Use ECC's installer when you want what symlinks cannot express: hooks, rules, agents, or
managed uninstall via its install-state tracking.

### Upstream checkouts this repo links into

Clone these to make the manifests resolve on a new machine:

| Clone | Repo | License |
|---|---|---|
| `~/src/ECC` | affaan-m/ECC | MIT |
| `~/src/mattpocock-skills` | mattpocock/skills | MIT |

`install.sh` reports `MISSING` and skips, rather than failing, when one is absent.

## Portability decisions

Deliberate constraints, so a later edit doesn't quietly break one harness:

- **No shell injection in skill bodies.** Claude Code can run `` !`cmd` `` (and ```` ```! ```` blocks)
  before the body reaches the model, which would make the `handoff` skill's git-state gathering
  deterministic instead of instructed. opencode has no documented equivalent, so those lines would
  most likely reach the model as literal text. Skill bodies stay as instructions the model follows.
- **No `${CLAUDE_SKILL_DIR}` / `${CLAUDE_*}` substitutions**, for the same reason. If a skill ever
  needs a bundled script, reference it by a path the model can resolve itself.
- **A skill body cannot document placeholder syntax at all.** Claude Code substitutes it before
  the model sees the body, so prose *about* injection becomes injection — backtick-quoting does
  not protect it. `/add-skill` shipped with exactly this bug and failed with
  `command not found: cmd`. Put such documentation in a sibling file the skill tells the model to
  read; substitution does not apply to files read at runtime. See
  [`skills/add-skill/reference.md`](skills/add-skill/reference.md).
- **Claude-Code-only frontmatter is fine.** `argument-hint`, `allowed-tools`, and
  `disable-model-invocation` are silently ignored by opencode rather than rejected, so they cost
  nothing. Behavioural guarantees they provide must be restated for opencode — see the permission
  section above.

If a skill ever genuinely needs a harness-specific feature, fork it into two files and say so here
rather than degrading it in one harness by accident.

## Adding a skill

1. `mkdir -p skills/<name>` and write `SKILL.md` with at minimum `name` + `description`.
2. List it in `claude/skills.txt`, `opencode/skills.txt`, or both — that choice is what
   decides where it gets installed.
3. For opencode prompter visibility, add `opencode/command/<name>.md` that says
   "Invoke the `<name>` skill and follow it exactly."
4. `./install.sh`, then restart opencode (it discovers at startup).
5. Commit. Other machines get it with `git pull` + `./install.sh`; edits to files already
   linked need no re-install.
