#!/bin/sh
# Claude Code status line script
# Displays: model | cwd | context % | rate limits (when available)

input=$(cat)

model=$(echo "$input" | jq -r '.model.display_name // "Claude"')
cwd=$(echo "$input" | jq -r '.workspace.current_dir // .cwd // ""')
# Shorten home directory to ~
home="$HOME"
cwd_short="${cwd#"$home"}"
if [ "$cwd_short" != "$cwd" ]; then
  cwd_short="~$cwd_short"
fi

used_pct=$(echo "$input" | jq -r '.context_window.used_percentage // empty')
remaining_pct=$(echo "$input" | jq -r '.context_window.remaining_percentage // empty')

five_pct=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty')
week_pct=$(echo "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty')

# Build context section
ctx_part=""
if [ -n "$used_pct" ] && [ -n "$remaining_pct" ]; then
  used_int=$(printf "%.0f" "$used_pct")
  ctx_part="ctx:${used_int}%"
fi

# Build rate limit section
rate_part=""
if [ -n "$five_pct" ]; then
  five_int=$(printf "%.0f" "$five_pct")
  rate_part="5h:${five_int}%"
fi
if [ -n "$week_pct" ]; then
  week_int=$(printf "%.0f" "$week_pct")
  if [ -n "$rate_part" ]; then
    rate_part="${rate_part} 7d:${week_int}%"
  else
    rate_part="7d:${week_int}%"
  fi
fi

# Assemble the status line
parts="${model}  ${cwd_short}"
if [ -n "$ctx_part" ]; then
  parts="${parts}  ${ctx_part}"
fi
if [ -n "$rate_part" ]; then
  parts="${parts}  ${rate_part}"
fi

printf "%s" "$parts"
