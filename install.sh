#!/usr/bin/env bash
# Symlink every skill in ./skills into the load paths of Claude Code and opencode.
# Idempotent. Re-run after adding a skill; edits to SKILL.md need no re-run.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_DIR="$REPO_DIR/skills"

# Verified against Claude Code and opencode 1.18.12.
# NOTE: opencode does NOT read ~/.claude/skills, despite what its docs claim,
# so each skill needs a link in both trees.
TARGET_DIRS=(
  "$HOME/.claude/skills"          # Claude Code
  "$HOME/.config/opencode/skills" # opencode
)

MODE=install
FORCE=0
for arg in "$@"; do
  case "$arg" in
    --uninstall) MODE=uninstall ;;
    --force)     FORCE=1 ;;
    -h|--help)   sed -n '2,4p' "$0"; echo "Usage: $0 [--uninstall] [--force]"; exit 0 ;;
    *) echo "unknown flag: $arg" >&2; exit 2 ;;
  esac
done

[ -d "$SRC_DIR" ] || { echo "no skills/ dir at $SRC_DIR" >&2; exit 1; }

linked=0 skipped=0 removed=0

for src in "$SRC_DIR"/*/; do
  [ -f "${src}SKILL.md" ] || continue
  name="$(basename "$src")"
  src="${src%/}"

  for target_dir in "${TARGET_DIRS[@]}"; do
    mkdir -p "$target_dir"
    link="$target_dir/$name"

    if [ "$MODE" = uninstall ]; then
      if [ -L "$link" ] && [ "$(readlink "$link")" = "$src" ]; then
        rm "$link"; echo "unlinked  $link"; removed=$((removed+1))
      elif [ -e "$link" ]; then
        echo "skipped   $link (not a link into this repo)"; skipped=$((skipped+1))
      fi
      continue
    fi

    if [ -L "$link" ]; then
      current="$(readlink "$link")"
      [ "$current" = "$src" ] && { echo "ok        $link"; linked=$((linked+1)); continue; }
      ln -sfn "$src" "$link"; echo "relinked  $link (was -> $current)"; linked=$((linked+1))
    elif [ -e "$link" ]; then
      # A real directory here would swallow the symlink if we used `ln -sfn`.
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
  done
done

echo
if [ "$MODE" = uninstall ]; then
  echo "removed $removed link(s), skipped $skipped"
else
  echo "$linked link(s) in place, skipped $skipped"
  echo
  echo "Claude Code : run /reload-skills (or restart)"
  echo "opencode    : picked up on next start; verify with 'opencode debug skill'"
fi
