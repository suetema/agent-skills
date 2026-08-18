#!/usr/bin/env bash
# Install skills and agents into Claude Code and opencode from two independent
# per-harness manifests, plus opencode's command wrappers.
#
#   claude/skills.txt    -> ~/.claude/skills/<name>            (work)
#   claude/agents.txt    -> ~/.claude/agents/<name>.md
#   opencode/skills.txt  -> ~/.config/opencode/skills/<name>   (private)
#   opencode/agents.txt  -> ~/.config/opencode/agent/<name>.md
#   opencode/command/    -> ~/.config/opencode/command/<name>.md
#
# Each manifest is the whole story for its harness: anything this repo previously
# linked there and that is no longer listed gets pruned. Nothing is ever copied.
# Written for bash 3.2 (macOS system bash) — no empty-array expansion under set -u.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Verified against Claude Code and opencode 1.18.12. opencode does NOT read
# ~/.claude/skills, so the two harnesses need separate link trees.
CLAUDE_SKILLS="$HOME/.claude/skills"
CLAUDE_AGENTS="$HOME/.claude/agents"
OC_SKILLS="$HOME/.config/opencode/skills"
OC_AGENTS="$HOME/.config/opencode/agent"   # singular, unlike Claude Code's agents/
OC_CMD_SRC="$REPO_DIR/opencode/command"
OC_CMD_TARGET="$HOME/.config/opencode/command"

# Records every link this script created, so a line deleted from a manifest can be
# pruned even when nothing references its source any more.
STATE_DIR="$HOME/.local/state/agent-skills"
STATE_FILE="$STATE_DIR/links.txt"

MODE=install
FORCE=0
for arg in "$@"; do
  case "$arg" in
    --uninstall) MODE=uninstall ;;
    --force)     FORCE=1 ;;
    -h|--help)   echo "Usage: $0 [--uninstall] [--force]"; exit 0 ;;
    *) echo "unknown flag: $arg" >&2; exit 2 ;;
  esac
done

linked=0 skipped=0 removed=0
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# resolve_path <raw> -> absolute path (repo-relative unless ~ or / prefixed)
resolve_path() {
  case "$1" in
    "~/"*) printf '%s\n' "$HOME/${1#\~/}" ;;
    /*)    printf '%s\n' "$1" ;;
    ./*)   printf '%s\n' "$REPO_DIR/${1#./}" ;;
    *)     printf '%s\n' "$REPO_DIR/$1" ;;
  esac
}

# read_manifest <file> -> "name<TAB>abs_path" per entry, comments and blanks stripped
read_manifest() {
  [ -f "$1" ] || return 0
  while IFS= read -r raw || [ -n "$raw" ]; do
    line="${raw%%#*}"
    line="$(printf '%s' "$line" | awk '{$1=$1;print}')"
    [ -n "$line" ] || continue
    n="$(printf '%s' "$line" | awk '{print $1}')"
    p="$(printf '%s' "$line" | awk '{print $2}')"
    if [ -z "$p" ]; then
      echo "MANIFEST  '$n' in $(basename "$(dirname "$1")")/$(basename "$1") has no path; skipping" >&2
      continue
    fi
    printf '%s\t%s\n' "$n" "$(resolve_path "$p")"
  done < "$1"
}

# link_one <source> <link path>
link_one() {
  src="$1"; link="$2"
  [ "$MODE" = install ] && printf '%s\n' "$link" >> "$WORK/current-links"
  if [ "$MODE" = uninstall ]; then
    if [ -L "$link" ] && [ "$(readlink "$link")" = "$src" ]; then
      rm "$link"; echo "unlinked  $link"; removed=$((removed+1))
    elif [ -e "$link" ]; then
      echo "skipped   $link (not a link into this repo)"; skipped=$((skipped+1))
    fi
    return
  fi
  if [ -L "$link" ]; then
    current="$(readlink "$link")"
    if [ "$current" = "$src" ]; then echo "ok        $link"; linked=$((linked+1)); return; fi
    ln -sfn "$src" "$link"; echo "relinked  $link (was -> $current)"; linked=$((linked+1))
  elif [ -e "$link" ]; then
    # A real file/dir here would be clobbered, or swallow the symlink, so never force silently.
    if [ "$FORCE" = 1 ]; then
      mv "$link" "$link.bak.$$"; ln -s "$src" "$link"
      echo "replaced  $link (original -> $link.bak.$$)"; linked=$((linked+1))
    else
      echo "SKIP      $link exists and is not a symlink; re-run with --force to move it aside" >&2
      skipped=$((skipped+1))
    fi
  else
    ln -s "$src" "$link"; echo "linked    $link"; linked=$((linked+1))
  fi
}

# Every source path any manifest mentions. A link in a harness dir is considered
# ours to prune only if it points at one of these, or anywhere inside this repo.
: > "$WORK/managed-sources"
for m in "$REPO_DIR/claude/skills.txt" "$REPO_DIR/opencode/skills.txt" \
         "$REPO_DIR/claude/agents.txt" "$REPO_DIR/opencode/agents.txt"; do
  read_manifest "$m" | cut -f2 >> "$WORK/managed-sources"
done

# install_set <manifest> <target dir> <suffix> <label>
install_set() {
  manifest="$1"; target_dir="$2"; suffix="$3"; label="$4"
  read_manifest "$manifest" > "$WORK/entries"
  : > "$WORK/wanted"

  while IFS="$(printf '\t')" read -r name src; do
    [ -n "${name:-}" ] || continue
    printf '%s\n' "$name$suffix" >> "$WORK/wanted"
    if [ "$MODE" = install ]; then
      # A directory skill needs SKILL.md; an agent is a single .md file.
      if [ -n "$suffix" ]; then
        [ -f "$src" ] || { echo "MISSING   $label $name -> $src (no such file)" >&2; skipped=$((skipped+1)); continue; }
      else
        [ -f "$src/SKILL.md" ] || { echo "MISSING   $label $name -> $src (no SKILL.md — is the source repo cloned?)" >&2; skipped=$((skipped+1)); continue; }
      fi
    fi
    # An agent written for Claude Code breaks opencode's ENTIRE config with
    # ConfigInvalidError, not just its own file. Refuse rather than link it.
    if [ "$MODE" = install ] && [ "$target_dir" = "$OC_AGENTS" ]; then
      if grep -qE '^tools:[[:space:]]*[A-Za-z]' "$src"; then
        echo "INVALID   $label $name: 'tools:' is a Claude-Code comma list; opencode needs an object map." >&2
        echo "          Linking it would break opencode's whole config. Convert it first — see" >&2
        echo "          skills/add-skill/reference.md. Skipping." >&2
        skipped=$((skipped+1)); continue
      fi
      if grep -qE '^model:[[:space:]]*[A-Za-z0-9._-]+[[:space:]]*$' "$src" && ! grep -qE '^model:[^#]*/' "$src"; then
        echo "INVALID   $label $name: 'model:' must be provider-qualified for opencode" >&2
        echo "          (e.g. openai/gpt-5.6-sol), not a bare alias like 'sonnet'. Skipping." >&2
        skipped=$((skipped+1)); continue
      fi
    fi
    mkdir -p "$target_dir"
    link_one "$src" "$target_dir/$name$suffix"
  done < "$WORK/entries"

  [ "$MODE" = install ] || return 0
  # Prune links we own that this manifest no longer lists.
  [ -d "$target_dir" ] || return 0
  for entry in "$target_dir"/*; do
    [ -L "$entry" ] || continue
    base="$(basename "$entry")"
    grep -qxF "$base" "$WORK/wanted" 2>/dev/null && continue
    tgt="$(readlink "$entry")"
    ours=no
    case "$tgt" in "$REPO_DIR"/*) ours=yes ;; esac
    [ "$ours" = yes ] || grep -qxF "$tgt" "$WORK/managed-sources" 2>/dev/null && ours=yes
    [ "$ours" = yes ] || continue
    rm "$entry"; echo "pruned    $entry (not listed for $label)"; removed=$((removed+1))
  done
}

install_set "$REPO_DIR/claude/skills.txt"   "$CLAUDE_SKILLS" ""    "claude skills"
install_set "$REPO_DIR/opencode/skills.txt" "$OC_SKILLS"     ""    "opencode skills"
install_set "$REPO_DIR/claude/agents.txt"   "$CLAUDE_AGENTS" ".md" "claude agents"
install_set "$REPO_DIR/opencode/agents.txt" "$OC_AGENTS"     ".md" "opencode agents"

# opencode command wrappers (Claude Code needs none — commands are merged into skills there)
if [ -d "$OC_CMD_SRC" ]; then
  for src in "$OC_CMD_SRC"/*.md; do
    [ -f "$src" ] || continue
    mkdir -p "$OC_CMD_TARGET"
    link_one "$src" "$OC_CMD_TARGET/$(basename "$src")"
  done
fi

# Anything we linked on a previous run and no longer want is now orphaned: its source
# may not be referenced by any manifest, so the per-directory pass above cannot see it.
if [ "$MODE" = install ]; then
  touch "$WORK/current-links"
  if [ -f "$STATE_FILE" ]; then
    while IFS= read -r old || [ -n "$old" ]; do
      [ -n "$old" ] || continue
      grep -qxF "$old" "$WORK/current-links" && continue
      if [ -L "$old" ]; then
        rm "$old"; echo "pruned    $old (no longer in any manifest)"; removed=$((removed+1))
      fi
    done < "$STATE_FILE"
  fi
  mkdir -p "$STATE_DIR"
  sort -u "$WORK/current-links" > "$STATE_FILE"
else
  # Uninstall: drop anything we ever recorded, then forget the state.
  if [ -f "$STATE_FILE" ]; then
    while IFS= read -r old || [ -n "$old" ]; do
      [ -n "$old" ] || continue
      if [ -L "$old" ]; then rm "$old"; echo "unlinked  $old"; removed=$((removed+1)); fi
    done < "$STATE_FILE"
    rm -f "$STATE_FILE"
  fi
fi

echo
if [ "$MODE" = uninstall ]; then
  echo "removed $removed link(s), skipped $skipped"
else
  echo "$linked link(s) in place, $removed pruned, skipped $skipped"
  echo
  echo "Claude Code : run /reload-skills (or restart)"
  echo "opencode    : restart it — skills, agents and commands are discovered at startup"
fi
