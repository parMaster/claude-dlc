#!/usr/bin/env bash
# Claude Code statusLine — based on robbyrussell Oh My Zsh theme

input=$(cat)

cwd=$(echo "$input" | jq -r '.workspace.current_dir // .cwd')
# Drop the " (1M context)" suffix; the ctx segment already covers the context window
model=$(echo "$input" | jq -r '.model.display_name // "" | sub(" \\([^)]* context\\)$"; "")')
used_pct=$(echo "$input" | jq -r '.context_window.used_percentage // empty')
session_pct=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty')
week_pct=$(echo "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty')
reset_at=$(echo "$input" | jq -r '.rate_limits.five_hour.resets_at // empty')
cache_expires=$(echo "$input" | jq -r '.prompt_cache.expires_at // empty | floor')

# Basename of current dir (like %c in robbyrussell)
dir=$(basename "$cwd")

# Git branch (skip optional lock to avoid contention)
git_branch=""
if git_out=$(GIT_OPTIONAL_LOCKS=0 git -C "$cwd" symbolic-ref --short HEAD 2>/dev/null); then
  git_branch="$git_out"
elif git_out=$(GIT_OPTIONAL_LOCKS=0 git -C "$cwd" rev-parse --short HEAD 2>/dev/null); then
  git_branch="$git_out"
fi

# Build the line
# Colors: cyan for dir, blue/red for git, yellow for context, dim for model
printf '\033[1;32m➜\033[0m '
printf '\033[0;36m%s\033[0m' "$dir"

if [ -n "$git_branch" ]; then
  git_status=$(GIT_OPTIONAL_LOCKS=0 git -C "$cwd" status --porcelain 2>/dev/null)
  if [ -n "$git_status" ]; then
    printf ' \033[1;34mgit:(\033[0;31m%s\033[1;34m)\033[0m \033[0;33m✗\033[0m' "$git_branch"
  else
    printf ' \033[1;34mgit:(\033[0;31m%s\033[1;34m)\033[0m' "$git_branch"
  fi
fi

# Dim pipe before each segment after git, so the dim segments don't blur together
sep() { printf ' \033[2m│\033[0m '; }

if [ -n "$model" ]; then
  sep
  printf '\033[2m%s\033[0m' "$model"
fi

if [ -n "$used_pct" ]; then
  ctx_color='\033[2m'
  if awk -v p="$used_pct" 'BEGIN { exit !(p > 30) }'; then
    ctx_color='\033[0;35m'
  fi
  sep
  printf "${ctx_color}ctx %.0f%%\033[0m" "$used_pct"
fi

# Minutes until the prompt cache goes cold; refreshInterval keeps it ticking while idle
if [ -n "$cache_expires" ]; then
  cache_left=$((cache_expires - $(date +%s)))
  sep
  if [ "$cache_left" -le 0 ]; then
    printf '\033[2mcache cold\033[0m'
  else
    cache_min=$(((cache_left + 59) / 60))
    cache_color='\033[2m'
    if [ "$cache_min" -le 5 ]; then
      cache_color='\033[0;33m'
    fi
    printf "${cache_color}cache %dm\033[0m" "$cache_min"
  fi
fi

if [ -n "$session_pct" ] && [ -n "$week_pct" ]; then
  reset_time=""
  if [ -n "$reset_at" ]; then
    reset_time=$(date -r "$reset_at" "+%l:%M%p" 2>/dev/null | tr -d ' ' | tr '[:upper:]' '[:lower:]')
  fi
  sep
  if [ -n "$reset_time" ]; then
    printf '\033[2m5h %.0f%% · 7d %.0f%% ↺%s\033[0m' "$session_pct" "$week_pct" "$reset_time"
  else
    printf '\033[2m5h %.0f%% · 7d %.0f%%\033[0m' "$session_pct" "$week_pct"
  fi
fi

printf '\n'
