#!/bin/bash
# Install the skill for one or more coding agents.
#
# Usage: ./scripts/install.sh [--link] [--project DIR] [TARGET...]
#
# Targets (default: agents claude):
#   agents   ~/.agents/skills   shared folder read by Codex, Gemini CLI, Cursor and GitHub Copilot
#   claude   ~/.claude/skills   Claude Code
#   codex    same as agents
#   gemini   ~/.gemini/skills
#   cursor   ~/.cursor/skills
#   copilot  ~/.copilot/skills
#
# --project DIR  install into DIR (a repository) instead of your home folder,
#                e.g. DIR/.agents/skills or DIR/.claude/skills
# --link         symlink instead of copying, so `git pull` in this repo updates the skill
set -euo pipefail
cd "$(dirname "$0")/.."
name=synthetic-data-generation
src="$PWD/skills/$name"
link=0; base="$HOME"; targets=()
while [ $# -gt 0 ]; do
  case "$1" in
    --link) link=1 ;;
    --project) base="$(cd "$2" && pwd)"; shift ;;
    -h|--help) sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) targets+=("$1") ;;
  esac
  shift
done
[ ${#targets[@]} -eq 0 ] && targets=(agents claude)

dir_for() {
  case "$1" in
    agents|codex) echo "$base/.agents/skills" ;;
    claude) echo "$base/.claude/skills" ;;
    gemini) echo "$base/.gemini/skills" ;;
    cursor) echo "$base/.cursor/skills" ;;
    copilot) echo "$base/.copilot/skills" ;;
    *) echo "unknown target: $1 (use agents, claude, codex, gemini, cursor or copilot)" >&2; exit 2 ;;
  esac
}

done_dirs=" "
for t in "${targets[@]}"; do
  d="$(dir_for "$t")"
  case "$done_dirs" in *" $d "*) continue ;; esac
  done_dirs="$done_dirs$d "
  dest="$d/$name"
  mkdir -p "$d"
  if [ -e "$dest" ] || [ -L "$dest" ]; then
    if [ -L "$dest" ] || grep -q "^name: *\"\{0,1\}$name\"\{0,1\} *$" "$dest/SKILL.md" 2>/dev/null; then
      rm -rf "$dest"
    else
      echo "skipped $dest: it exists and isn't this skill" >&2
      continue
    fi
  fi
  if [ "$link" = 1 ]; then ln -s "$src" "$dest"; how="linked"; else cp -R "$src" "$dest"; how="copied"; fi
  echo "$how -> $dest"
done
