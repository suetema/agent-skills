---
name: add-skill
description: Add a skill to the agent-skills repo correctly — authored here or linked from an upstream checkout — and install it for Claude Code, opencode, or both. Use when the user wants to add, move, or remove a skill, or asks where a skill should live.
argument-hint: "[skill name or upstream path]"
allowed-tools: [Read, Write, Edit, Bash, Glob, Grep]
disable-model-invocation: true
metadata:
  origin: agent-skills
  agents: claude-code, opencode
---

# Add a skill to agent-skills

The repo is normally at `~/src/agent-skills`. Confirm before editing:

```bash
git -C ~/src/agent-skills remote -v   # expect suetema/agent-skills
```

If it is somewhere else, resolve it from an installed skill — every installed skill is a
symlink into the repo: `readlink ~/.claude/skills/handoff` or
`readlink ~/.config/opencode/skills/handoff`.

Read the repo's `README.md` before making structural changes. It records verified harness
behaviour and the reasons behind the layout; do not re-derive them.

## Two kinds of skill — pick the right one

**Authored here** — the skill is ours to maintain. Create `skills/<name>/SKILL.md`.

**Linked from elsewhere** — the skill belongs to an upstream repo (ECC and similar).
**Never copy it in.** Add a manifest line pointing at the existing checkout so upstream stays
the source of truth and `git pull` there keeps it current.

Given a URL rather than a local path, clone the upstream repo once and link into the clone:

```bash
git clone <repo-url> ~/src/<repo-name>       # skip if already cloned
ls ~/src/<repo-name>/<path/to/skill>/SKILL.md
```

Then use `~/src/<repo-name>/<path/to/skill>` as the manifest path. Do not download a single
`SKILL.md` on its own — a skill may reference sibling files, and a clone can be updated with
`git pull` while a stray copy cannot. Check the upstream license before adding it to a manifest;
record it in the manifest comment as is done for ECC.

## The decision that matters: which harness

Claude Code is **work**. opencode is **private projects**. There is no shared default — a
skill is installed exactly where it is listed:

| Manifest | Installs to |
|---|---|
| `claude/skills.txt` | `~/.claude/skills/<name>/` |
| `opencode/skills.txt` | `~/.config/opencode/skills/<name>/` |

Ask the user which one if it is not obvious from the skill's purpose. Listing it in both is
fine and normal for general-purpose tooling like `handoff`.

Manifest format — `~` expands to `$HOME`, `./` is repo-relative, `#` starts a comment:

```
handoff          ./skills/handoff
market-research  ~/src/ECC/skills/market-research
```

The `<name>` column is the installed name and becomes `/<name>`. It need not match the
upstream directory, so rename on the way in when two sources collide.

## Before adding, check the name

- Already in either manifest? `grep -rn "<name>" claude/skills.txt opencode/skills.txt`
- Colliding with a **Claude Code bundled skill**? `/code-review`, `/security-review`,
  `/simplify`, `/run`, `/init` and friends already exist. ECC's `security-review` is exactly
  this case, which is why it stays opencode-only.
- Colliding with something already installed?
  `ls ~/.claude/skills ~/.config/opencode/skills`

## Writing a SKILL.md

Required frontmatter is `name` and `description`. The description is what a model reads when
deciding whether to invoke the skill, so state both what it does and when to use it.

**Read `~/src/agent-skills/skills/add-skill/reference.md` before writing the body.** It lists
the frontmatter each harness honors, the portability rules that keep one file working in both,
and the opencode wrapper template.

That content is deliberately not inlined here. Claude Code substitutes placeholder syntax in a
skill body before the model sees it, so a skill cannot safely document that syntax in its own
body — the reference file explains the failure this caused.

## Steps

1. Create `skills/<name>/SKILL.md`, or identify the upstream path for a linked skill.
2. Add the line to `claude/skills.txt`, `opencode/skills.txt`, or both.
3. For opencode prompter visibility, add `opencode/command/<name>.md`. opencode lists
   skill-sourced entries only under `/skills`; a same-named command overrides the entry so it
   appears in the `/` autocomplete. Copy the template from `reference.md` and keep the wrapper
   thin, so the skill stays the single source of truth. Claude Code needs no wrapper — commands
   and skills are the same mechanism there.
4. If the skill should be explicit-invocation-only in opencode, add it to
   `permission.skill` in `~/.config/opencode/opencode.json` as `"ask"`. That file is
   machine-local, so note it in the README — it does not travel with a clone.
5. Run `./install.sh`.
6. Verify:

   ```bash
   ls ~/.claude/skills ~/.config/opencode/skills   # links present where expected
   opencode debug skill | grep -c '"<name>"'        # opencode sees it
   ```

   In Claude Code, `/reload-skills`. opencode needs a full restart.
7. Commit and push. Explain in the message *why* a skill is scoped to one harness, not just
   that it is.

## Agents

Agents work the same way, through `claude/agents.txt` and `opencode/agents.txt`, with one
critical difference: **the two harnesses use incompatible agent formats.** A skill body is
portable; an agent definition is not.

| Manifest | Installs to | Path points at |
|---|---|---|
| `claude/agents.txt` | `~/.claude/agents/<name>.md` | a single `.md` file |
| `opencode/agents.txt` | `~/.config/opencode/agent/<name>.md` | a single `.md` file |

**ECC's agents (`~/src/ECC/agents/*.md`) are Claude Code format.** Link them into Claude Code
directly — they work as-is. Do **not** list them for opencode: their `tools: Read, Grep, Glob`
comma list is invalid there and produces a `ConfigInvalidError` that invalidates opencode's
**entire** config, not just that file. Their `model: sonnet` is a bare Anthropic alias, which
opencode also rejects — and would pin an Anthropic model in a harness configured for other
providers.

`install.sh` refuses these rather than linking them, printing `INVALID ... 'tools:' is a
Claude-Code comma list`. If you see that, the agent needs converting, not forcing.

To get equivalent behaviour in opencode, author a native agent in this repo as
`agents/<name>.md` and list that. See `reference.md` for the field-by-field differences and a
conversion recipe.

## Moving or removing a skill

Manifests are authoritative, not additive. Move a line between manifests, or delete it, and
the next `./install.sh` prunes the stale link. Do not remove links by hand.

Pruning works off a state file at `~/.local/state/agent-skills/links.txt` recording every link
the script created, so a line deleted from every manifest is still cleaned up. Links this repo
never created are left alone.

## Do not

- Copy an upstream skill into `skills/`. Link it.
- List a Claude-format agent in `opencode/agents.txt`. It breaks opencode's whole config.
- Add a skill to both harnesses "to be safe". The split is deliberate: work vs private.
- Hand-edit `~/.claude/skills` or `~/.config/opencode/skills`. The manifests decide.
- Add `skills.paths` entries to `~/.config/opencode/opencode.json`. That is the
  machine-local mechanism this repo replaced.
