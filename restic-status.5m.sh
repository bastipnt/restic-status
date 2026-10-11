#!/usr/bin/env bash
#
# <xbar.title>Restic Backup Status</xbar.title>
# <xbar.version>v1.0.0</xbar.version>
# <xbar.desc>Shows the status of resticprofile backups by reading resticprofile status files.</xbar.desc>
# <xbar.dependencies>bash,jq,resticprofile</xbar.dependencies>
# <xbar.abouturl>https://github.com/bastipnt/restic-status</xbar.abouturl>
# <swiftbar.hideRunInTerminal>true</swiftbar.hideRunInTerminal>
# <swiftbar.hideDisablePlugin>false</swiftbar.hideDisablePlugin>
# <swiftbar.environment>[RESTIC_STATUS_FILES=~/.config/resticprofile/status.json, RESTIC_MAX_AGE_HOURS=26, RESTICPROFILE_CONFIG=]</swiftbar.environment>
#
# Configuration (environment variables, or KEY=value lines in the config file,
# which takes precedence; default ~/.config/restic-status/config):
#
#   RESTIC_STATUS_FILES      Comma or colon separated list of resticprofile
#                            status files (the `status-file` option).
#   RESTIC_MAX_AGE_HOURS     Warn when the last successful backup is older
#                            than this (default 26, 0 disables).
#   RESTIC_MAX_AGE_HOURS_<profile>
#                            Per profile override (non-alphanumeric characters
#                            in the profile name replaced by "_").
#   RESTIC_SHOW_COUNT        1 = show the number of problems next to the icon.
#   RESTIC_DETECT_RUNNING    1 = show a "running" icon while restic backs up
#                            (default 1).
#   RESTICPROFILE_BIN        resticprofile binary (default: found in PATH).
#   RESTICPROFILE_CONFIG     Passed as --config to resticprofile for
#                            "Run backup now" (default: resticprofile's own
#                            lookup).

set -f  # no globbing: menu text may contain "*"

export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"

CONFIG_FILE="${RESTIC_STATUS_CONFIG:-$HOME/.config/restic-status/config}"
if [ -f "$CONFIG_FILE" ]; then
  # shellcheck disable=SC1090
  . "$CONFIG_FILE"
fi

RESTIC_STATUS_FILES="${RESTIC_STATUS_FILES:-$HOME/.config/resticprofile/status.json}"
RESTIC_MAX_AGE_HOURS="${RESTIC_MAX_AGE_HOURS:-26}"
RESTIC_SHOW_COUNT="${RESTIC_SHOW_COUNT:-0}"
RESTIC_DETECT_RUNNING="${RESTIC_DETECT_RUNNING:-1}"
RESTICPROFILE_BIN="${RESTICPROFILE_BIN:-$(command -v resticprofile 2>/dev/null || echo resticprofile)}"
RESTICPROFILE_CONFIG="${RESTICPROFILE_CONFIG:-}"
SELF="${SWIFTBAR_PLUGIN_PATH:-$0}"

ICON_OK="externaldrive.badge.checkmark"
ICON_STALE="externaldrive.badge.exclamationmark"
ICON_ERROR="externaldrive.badge.xmark"
ICON_RUNNING="arrow.triangle.2.circlepath"
ICON_UNKNOWN="externaldrive.badge.questionmark"

# Field / line separators used between jq and bash. Non-whitespace, so empty
# fields are preserved by `read` (tabs would collapse).
FS=$'\x1f'
LS=$'\x1e'

expand_path() {
  # shellcheck disable=SC2088
  case "$1" in
    "~") printf '%s\n' "$HOME" ;;
    "~/"*) printf '%s\n' "$HOME/${1#\~/}" ;;
    *) printf '%s\n' "$1" ;;
  esac
}

# ---------------------------------------------------------------------------
# Menu actions (invoked by SwiftBar via bash="$SELF" param1=...)
# ---------------------------------------------------------------------------

case "${1:-}" in
  --run)
    profile="$2"
    log_dir="$HOME/Library/Logs/restic-status"
    mkdir -p "$log_dir"
    if [ -n "$RESTICPROFILE_CONFIG" ]; then
      nohup "$RESTICPROFILE_BIN" --config "$(expand_path "$RESTICPROFILE_CONFIG")" --name "$profile" backup \
        >"$log_dir/$profile.log" 2>&1 </dev/null &
    else
      nohup "$RESTICPROFILE_BIN" --name "$profile" backup \
        >"$log_dir/$profile.log" 2>&1 </dev/null &
    fi
    exit 0
    ;;
  --edit-config)
    if [ ! -f "$CONFIG_FILE" ]; then
      mkdir -p "$(dirname "$CONFIG_FILE")"
      cat >"$CONFIG_FILE" <<EOF
# restic-status configuration (shell KEY=value syntax)
# Multiple status files are separated by commas.
RESTIC_STATUS_FILES="$RESTIC_STATUS_FILES"
RESTIC_MAX_AGE_HOURS=$RESTIC_MAX_AGE_HOURS
# RESTIC_MAX_AGE_HOURS_myprofile=170
# RESTIC_SHOW_COUNT=1
# RESTIC_DETECT_RUNNING=1
# RESTICPROFILE_BIN=/opt/homebrew/bin/resticprofile
# RESTICPROFILE_CONFIG=~/.config/resticprofile/profiles.toml
EOF
    fi
    open -t "$CONFIG_FILE"
    exit 0
    ;;
esac

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

find_jq() {
  for candidate in "${JQ_BIN:-}" "$(command -v jq 2>/dev/null)" /usr/bin/jq /opt/homebrew/bin/jq /usr/local/bin/jq; do
    if [ -n "$candidate" ] && [ -x "$candidate" ]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  return 1
}

human_bytes() {
  [ -z "$1" ] && return
  awk -v b="$1" 'BEGIN {
    split("B KiB MiB GiB TiB PiB", u, " "); i = 1
    while (b >= 1024 && i < 6) { b /= 1024; i++ }
    if (i == 1) printf "%d %s", b, u[i]; else printf "%.1f %s", b, u[i]
  }'
}

human_duration() {
  s="$1"
  [ -z "$s" ] && return
  if [ "$s" -lt 60 ]; then printf '%ds' "$s"
  elif [ "$s" -lt 3600 ]; then printf '%dm %ds' $((s / 60)) $((s % 60))
  else printf '%dh %dm' $((s / 3600)) $((s % 3600 / 60))
  fi
}

human_age() {
  a="$1"
  if [ -z "$a" ]; then printf 'never'; return; fi
  if [ "$a" -lt 0 ]; then a=0; fi
  if [ "$a" -lt 60 ]; then printf 'just now'
  elif [ "$a" -lt 3600 ]; then printf '%dm ago' $((a / 60))
  elif [ "$a" -lt 172800 ]; then printf '%dh ago' $((a / 3600))
  else printf '%dd ago' $((a / 86400))
  fi
}

format_time() {
  [ -z "$1" ] && return
  date -r "$1" '+%Y-%m-%d %H:%M' 2>/dev/null || date -d "@$1" '+%Y-%m-%d %H:%M' 2>/dev/null
}

max_age_for() {
  san=$(printf '%s' "$1" | tr -c 'A-Za-z0-9_' '_')
  eval "v=\${RESTIC_MAX_AGE_HOURS_${san}:-}"
  printf '%s\n' "${v:-$RESTIC_MAX_AGE_HOURS}"
}

# Free text shown in the menu must not contain the SwiftBar parameter
# separator and must not start with "-" (submenu marker).
menu_text() {
  printf '%s' "$1" | tr '|' '/' | cut -c1-"${2:-120}" | sed 's/^-/ -/'
}

# Plain text line without emoji / SF Symbol substitution.
TXT="emojize=false symbolize=false"

# ---------------------------------------------------------------------------
# Parsing
# ---------------------------------------------------------------------------

# One record per profile, fields separated by $FS:
# profile, backup_success, backup_epoch, duration, bytes_added, bytes_total,
# files_new, files_changed, files_unmodified, error, stderr_tail, other_commands
# other_commands: name:success:epoch entries joined by ","
# shellcheck disable=SC2016
JQ_PROGRAM='
def epoch:
  if type != "string" or . == "" then null else
  (try (
    capture("^(?<dt>[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2})(\\.[0-9]+)?(?<tz>Z|[+-][0-9]{2}:?[0-9]{2})?$")
    | (.dt + "Z" | fromdateiso8601) - (
        if (.tz // "Z") == "Z" then 0
        else .tz | (if startswith("-") then -1 else 1 end)
                 * ((.[1:3] | tonumber) * 3600 + (.[-2:] | tonumber) * 60)
        end)
  ) catch null) end;
def s: if . == null then "" else tostring end;
def clean: s | gsub("[\\x00-\\x1f]+"; " ");
def b: if . == null then "" elif . then "1" else "0" end;
(.profiles // {}) | to_entries[] | .key as $name | (.value // {}) as $p |
($p.backup // {}) as $bk |
[ $name,
  (if $p.backup == null then "" else ($bk.success | b) end),
  ($bk.time | epoch | s),
  ($bk.duration | s),
  ($bk.bytes_added | s),
  ($bk.bytes_total | s),
  ($bk.files_new | s),
  ($bk.files_changed | s),
  ($bk.files_unmodified | s),
  ($bk.error | clean),
  ($bk.stderr | s | split("\n") | map(gsub("[\\x00-\\x1f]+"; " ") | select(test("\\S"))) | .[-5:] | join("\u001e")),
  ([ $p | to_entries[] | select(.key != "backup" and (.value | type) == "object")
     | "\(.key):\(.value.success | b):\(.value.time | epoch | s)" ] | join(","))
] | join("\u001f")
'

JQ=$(find_jq) || {
  echo "? | sfimage=$ICON_UNKNOWN"
  echo "---"
  echo "jq not found"
  echo "Install with: brew install jq | $TXT"
  exit 0
}

NOW="${RESTIC_NOW:-$(date +%s)}"

# Collected output for the dropdown (filled while parsing).
BODY=""
add() { BODY="$BODY$1
"; }

total=0
n_ok=0
n_stale=0
n_error=0
n_unknown=0

# shellcheck disable=SC2020
files=$(printf '%s' "$RESTIC_STATUS_FILES" | tr ',:' '\n\n')
n_files=$(printf '%s\n' "$files" | grep -c '[^[:space:]]')

while IFS= read -r raw_file; do
  file=$(expand_path "$(printf '%s' "$raw_file" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')")
  [ -z "$file" ] && continue
  short_file="$file"
  # shellcheck disable=SC2088
  case "$file" in "$HOME"/*) short_file="~/${file#"$HOME"/}" ;; esac

  if [ ! -f "$file" ]; then
    total=$((total + 1)); n_error=$((n_error + 1))
    add "$(menu_text "$(basename "$file")") — file not found | sfimage=xmark.circle $TXT"
    add "--$(menu_text "$short_file" 200) | $TXT"
    add "--Set status-file in your resticprofile config | $TXT"
    continue
  fi

  if ! records=$("$JQ" -r "$JQ_PROGRAM" "$file" 2>/dev/null); then
    total=$((total + 1)); n_error=$((n_error + 1))
    add "$(menu_text "$(basename "$file")") — cannot parse | sfimage=xmark.circle $TXT"
    add "--$(menu_text "$short_file" 200) | $TXT"
    add "--Open status file | bash=/usr/bin/open param1=-t param2=\"$file\" terminal=false"
    continue
  fi

  [ -z "$records" ] && continue

  while IFS="$FS" read -r name success epoch duration bytes_added bytes_total \
    files_new files_changed files_unmodified error stderr_tail others; do
    [ -z "$name" ] && continue
    total=$((total + 1))

    age=""
    [ -n "$epoch" ] && age=$((NOW - epoch))
    max_age=$(max_age_for "$name")

    # Any failed command (backup, check, forget, ...) marks the profile as failed.
    other_failed=0
    old_ifs="$IFS"; IFS=','
    for o in $others; do
      case "$o" in *:0:*) other_failed=1 ;; esac
    done
    IFS="$old_ifs"

    if [ "$success" = "0" ] || [ "$other_failed" = "1" ]; then
      state=error; n_error=$((n_error + 1)); icon="xmark.circle"
    elif [ -z "$success" ] || [ -z "$epoch" ]; then
      state=unknown; n_unknown=$((n_unknown + 1)); icon="questionmark.circle"
    elif [ "$max_age" -gt 0 ] 2>/dev/null && [ "$age" -gt $((max_age * 3600)) ]; then
      state=stale; n_stale=$((n_stale + 1)); icon="exclamationmark.triangle"
    else
      state=ok; n_ok=$((n_ok + 1)); icon="checkmark.circle"
    fi

    case "$state" in
      error) [ "$success" = "0" ] && label="backup failed" || label="failed" ;;
      unknown) label="no backup recorded" ;;
      *) label="$(human_age "$age")" ;;
    esac
    if [ "$state" = "error" ] && [ -n "$age" ]; then
      label="$label $(human_age "$age")"
    fi

    add "$(menu_text "$name" 60) — $label | sfimage=$icon $TXT"
    if [ -n "$epoch" ]; then
      add "--Last backup: $(format_time "$epoch") ($(human_age "$age")) | $TXT"
    fi
    [ "$state" = "stale" ] && add "--Older than ${max_age}h | sfimage=exclamationmark.triangle $TXT"
    [ -n "$duration" ] && add "--Duration: $(human_duration "$duration") | $TXT"
    if [ -n "$bytes_added" ] || [ -n "$bytes_total" ]; then
      size="Added: $(human_bytes "${bytes_added:-0}")"
      [ -n "$bytes_total" ] && size="$size · Processed: $(human_bytes "$bytes_total")"
      add "--$size | $TXT"
    fi
    if [ -n "$files_new" ] || [ -n "$files_changed" ]; then
      add "--Files: ${files_new:-0} new, ${files_changed:-0} changed, ${files_unmodified:-0} unmodified | $TXT"
    fi

    old_ifs="$IFS"; IFS=','
    for o in $others; do
      cmd="${o%%:*}"; rest="${o#*:}"; ok="${rest%%:*}"; t="${rest#*:}"
      case "$ok" in 1) res="OK"; ci="checkmark" ;; 0) res="FAILED"; ci="xmark" ;; *) res="?"; ci="questionmark" ;; esac
      line="--$(menu_text "$cmd" 30): $res"
      [ -n "$t" ] && line="$line · $(human_age $((NOW - t)))"
      add "$line | sfimage=$ci $TXT"
    done
    IFS="$old_ifs"

    if [ -n "$error" ]; then
      add "-----"
      add "--Error: $(menu_text "$error") | $TXT"
    fi
    if [ -n "$stderr_tail" ]; then
      [ -z "$error" ] && add "-----"
      add "--Output: | $TXT"
      old_ifs="$IFS"; IFS="$LS"
      for l in $stderr_tail; do
        add "--  $(menu_text "$l") | font=Menlo size=11 $TXT"
      done
      IFS="$old_ifs"
    fi

    add "-----"
    add "--Run backup now | bash=\"$SELF\" param1=--run param2=\"$name\" terminal=false refresh=true sfimage=play"
    [ "$n_files" -gt 1 ] && add "--$(menu_text "$short_file" 200) | $TXT"
    add "--Open status file | bash=/usr/bin/open param1=-t param2=\"$file\" terminal=false"
  done <<EOF
$records
EOF
done <<EOF
$files
EOF

running=0
if [ "$RESTIC_DETECT_RUNNING" = "1" ] && pgrep -f '(^|/)restic( .*)? backup' >/dev/null 2>&1; then
  running=1
fi

# ---------------------------------------------------------------------------
# Output
# ---------------------------------------------------------------------------

problems=$((n_error + n_stale))
if [ "$running" = "1" ]; then
  icon="$ICON_RUNNING"
elif [ "$n_error" -gt 0 ]; then
  icon="$ICON_ERROR"
elif [ "$n_stale" -gt 0 ]; then
  icon="$ICON_STALE"
elif [ "$n_ok" -gt 0 ]; then
  icon="$ICON_OK"
else
  icon="$ICON_UNKNOWN"
fi

title=""
if [ "$RESTIC_SHOW_COUNT" = "1" ] && [ "$problems" -gt 0 ]; then
  title="$problems"
fi
echo "$title | sfimage=$icon"
echo "---"

if [ "$total" -eq 0 ]; then
  summary="No backups found"
elif [ "$problems" -eq 0 ] && [ "$n_unknown" -eq 0 ]; then
  if [ "$total" -eq 1 ]; then summary="Backup OK"; else summary="All $total backups OK"; fi
else
  summary=""
  [ "$n_error" -gt 0 ] && summary="$n_error failed"
  [ "$n_stale" -gt 0 ] && summary="${summary:+$summary, }$n_stale overdue"
  [ "$n_unknown" -gt 0 ] && summary="${summary:+$summary, }$n_unknown unknown"
  summary="$summary (of $total)"
fi
echo "$summary | $TXT"
[ "$running" = "1" ] && echo "Backup running… | sfimage=$ICON_RUNNING $TXT"
echo "---"
printf '%s' "$BODY"
echo "---"
echo "Refresh | refresh=true sfimage=arrow.clockwise"
echo "Edit configuration… | bash=\"$SELF\" param1=--edit-config terminal=false sfimage=gearshape"
