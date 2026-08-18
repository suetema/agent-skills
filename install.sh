#!/usr/bin/env bash
# Install this repo's skills into Claude Code and opencode, link the externally
# maintained skills listed in external-skills.txt, and install the opencode command
# wrappers that put each skill in opencode's / prompter.
#
# Idempotent, and authoritative: an entry that stops targeting a harness has its
# link pruned there on the next run.
# Written for bash 3.2 (macOS system bash) — no empty-array expansion under set -u.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_SRC="$REPO_DIR/skills"
OC_CMD_SRC="$REPO_DIR/opencode/command"
EXTERNAL_MANIFEST="$REPO_DIR/external-skills.txt"

# Verified against Claude Code and opencode 1.18.12.
# NOTE: opencode does NOT read ~/.claude/skills, despite what its docs claim,
# so a skill wanted in both harnesses needs a link in both trees.
CLAUDE_SKILLS="$HOME/.claude/skills"
OC_SKILLS="$HOME/.config/opencode/skills"
ALL_SKILL_DIRS="$CLAUDE_SKILLS $OC_SKILLS"
# opencode lists skill-sourced entries only under /skills. A same-named command
# overrides the entry as source=command, which is what the / prompter shows.
OC_CMD_TARGET="$HOME/.config/opencode/command"

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

# link_one <source> <link path>
link_one() {
  src="$1"; link="$2"
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

# resolve_targets <spec> -> space-separated skill dirs ("" when the spec is unusable)
resolve_targets() {
  spec="$1"; out=""
  case ",$spec," in *,both,*) echo "$ALL_SKILL_DIRS"; return ;; esac
  case ",$spec," in *,claude,*)   out="$out $CLAUDE_SKILLS" ;; esac
  case ",$spec," in *,opencode,*) out="$out $OC_SKILLS" ;; esac
  echo "$out"
}

[ -d "$SKILL_SRC" ] || { echo "no skills/ dir at $SKILL_SRC" >&2; exit 1; }

# --- skills maintained here: always both harnesses ---
for src in "$SKILL_SRC"/*/; do
  [ -f "${src}SKILL.md" ] || continue
  name="$(basename "$src")"; src="${src%/}"
  for target_dir in $ALL_SKILL_DIRS; do
    mkdir -p "$target_dir"
    link_one "$src" "$target_dir/$name"
  done
done

# --- skills maintained elsewhere: linked from their upstream checkout, never copied ---
if [ -f "$EXTERNAL_MANIFEST" ]; then
  while IFS= read -r raw || [ -n "$raw" ]; do
    line="${raw%%#*}"
    line="$(printf '%s' "$line" | awk '{$1=$1;print}')"
    [ -n "$line" ] || continue
    name="$(printf '%s' "$line" | awk '{print $1}')"
    path="$(printf '%s' "$line" | awk '{print $2}')"
    spec="$(printf '%s' "$line" | awk '{print $3}')"
    [ -n "$spec" ] || spec=both
    if [ -z "$path" ]; then
      echo "MANIFEST  '$name' has no path; skipping" >&2; skipped=$((skipped+1)); continue
    fi
    path="${path/#\~/$HOME}"

    if [ "$MODE" = uninstall ]; then
      # Ignore targeting on uninstall so nothing is left behind.
      for target_dir in $ALL_SKILL_DIRS; do link_one "$path" "$target_dir/$name"; done
      continue
    fi

    # A vanished upstream checkout is a warning, not a failure.
    if [ ! -f "$path/SKILL.md" ]; then
      echo "MISSING   $name -> $path (no SKILL.md — is the source repo cloned?)" >&2
      skipped=$((skipped+1)); continue
    fi

    dirs="$(resolve_targets "$spec" | awk '{$1=$1;print}')"
    if [ -z "$dirs" ]; then
      echo "MANIFEST  '$name' has unknown targets '$spec' (use both|claude|opencode)" >&2
      skipped=$((skipped+1)); continue
    fi

    for target_dir in $dirs; do
      mkdir -p "$target_dir"
      link_one "$path" "$target_dir/$name"
    done

    # The manifest is authoritative: drop our links from harnesses it no longer targets.
    for other in $ALL_SKILL_DIRS; do
      case " $dirs " in *" $other "*) continue ;; esac
      stale="$other/$name"
      if [ -L "$stale" ] && [ "$(readlink "$stale")" = "$path" ]; then
        rm "$stale"; echo "pruned    $stale (no longer targeted)"; removed=$((removed+1))
      fi
    done
  done < "$EXTERNAL_MANIFEST"
fi

# --- opencode command wrappers ---
if [ -d "$OC_CMD_SRC" ]; then
  for src in "$OC_CMD_SRC"/*.md; do
    [ -f "$src" ] || continue
    mkdir -p "$OC_CMD_TARGET"
    link_one "$src" "$OC_CMD_TARGET/$(basename "$src")"
  done
fi

echo
if [ "$MODE" = uninstall ]; then
  echo "removed $removed link(s), skipped $skipped"
else
  echo "$linked link(s) in place, $removed pruned, skipped $skipped"
  echo
  echo "Claude Code : run /reload-skills (or restart)"
  echo "opencode    : restart it — skills and commands are discovered at startup"
  echo "              verify with 'opencode debug skill' and the / prompter"
fi
