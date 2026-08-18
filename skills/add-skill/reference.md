# add-skill reference

Read by the `add-skill` skill at runtime. It lives in a separate file **on purpose**: Claude
Code performs substitution on a skill's body before the model sees it, so literal placeholder
syntax cannot be written safely in `SKILL.md`. It is inert here because this file is read as a
file, not rendered as skill content.

## Why this file exists (the bug that created it)

`SKILL.md` originally contained the sentence "Do not use !\`cmd\` shell injection". Claude Code
recognised that as an actual injection directive and ran `cmd`, so `/add-skill` failed with
`command not found: cmd`. The warning against shell injection *was* shell injection.

Three substitutions apply to a skill body, all of them traps for documentation:

| Written in a skill body | What actually happens |
|---|---|
| `!` immediately followed by a backtick-quoted command | The command is executed; its output replaces the text. Recognised when the `!` starts a line or follows whitespace. Backtick-quoting it in prose does **not** protect it. |
| A fence opened with three backticks then `!` | Every line in the block is executed. |
| `${CLAUDE_SKILL_DIR}`, `${CLAUDE_PROJECT_DIR}`, `${CLAUDE_SESSION_ID}`, `${CLAUDE_EFFORT}` | Silently replaced with real values. |
| `$ARGUMENTS`, `$ARGUMENTS[N]`, `$0`, `$1`, `$name` | Replaced with the invocation's arguments. An example template containing one gets corrupted. |

If a skill needs to *document* any of these, put it in a file like this one and have `SKILL.md`
say to read it.

## Frontmatter

Required: `name`, `description`. The description is what a model reads when deciding whether to
invoke, so cover both what it does and when to use it.

Honored by **Claude Code only** — opencode recognises just `name`, `description`, `license`,
`compatibility`, `metadata` and silently ignores the rest, which is why one file serves both:

| Field | Effect |
|---|---|
| `disable-model-invocation: true` | Only the user can invoke. Also keeps the description out of context. Use for side effects or user-controlled timing. |
| `user-invocable: false` | Only the model can invoke. For background knowledge, not actions. |
| `argument-hint` | Autocomplete hint. |
| `allowed-tools` | A permission **grant** for the invoking turn, not a restriction. Clears on the next message. |
| `arguments` | Named positional arguments. |

Honored by **opencode only**: `metadata` (string→string map).

## Portability rules for skill bodies

Both harnesses read the same file, so the body must work in both:

- No shell injection, in either the inline or fenced form. opencode has no equivalent, so those
  lines would reach its model as literal text. Write instructions the model follows instead.
- No `${CLAUDE_*}` substitutions, for the same reason.
- Claude-Code-only *frontmatter* is fine — opencode ignores unknown fields rather than
  rejecting them. Only the **body** must stay neutral.

Behavioural guarantees from Claude-only frontmatter must be restated for opencode. There is no
`disable-model-invocation` equivalent, so add the skill to `permission.skill` in
`~/.config/opencode/opencode.json` as `"ask"`. That file is machine-local and does not travel
with a clone, so record it in the repo README.

## opencode command wrapper template

opencode lists skill-sourced entries only under its `/skills` picker; they do not appear in the
`/` autocomplete. A command with the same name as a skill overrides the entry with
`source: command`, which the prompter does list. Keep the wrapper thin so `SKILL.md` stays the
single source of truth.

Write `opencode/command/<name>.md`:

```markdown
---
description: <one line, shown in the opencode TUI>
---

Invoke the `<name>` skill and follow it exactly.

<what the arguments mean>: $ARG<remove-this>UMENTS
```

Delete the `<remove-this>` marker when you write the real file — it is only here so this
reference does not itself get substituted. opencode parses the placeholder and passes arguments
through. Claude Code needs no wrapper: commands and skills are the same mechanism there.

## Verifying an install

```bash
ls ~/.claude/skills ~/.config/opencode/skills     # links present where expected
opencode debug skill                              # opencode's view; grep for the name
```

For the prompter specifically, opencode's local API is authoritative:

```bash
opencode serve --port 4799 &
curl -s http://127.0.0.1:4799/command | python3 -m json.tool | grep -A2 '"<name>"'
# source: "command" -> in the / prompter;  source: "skill" -> only under /skills
```

Claude Code: `/reload-skills`. opencode: full restart.
