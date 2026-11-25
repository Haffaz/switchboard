# shellcheck shell=bash
# Core helpers for cprof. Sourced by bin/cprof and by the tests.
# Nothing here launches apps or touches Keychain.

CPROF_HOME="${CPROF_HOME:-$HOME/.claude-profiles}"
CPROF_DEFAULT_CLI_DIR="${CPROF_DEFAULT_CLI_DIR:-$HOME/.claude}"
CPROF_DESKTOP_BUNDLE_ID="com.anthropic.claudefordesktop"
CPROF_PROFILE_FILE=".claude-profile"
CPROF_NAME_RE='^[a-z0-9][a-z0-9_-]{0,31}$'

# Items in ~/.claude that every profile links to, so rules, agents and
# skills stay in one place. Auth (.claude.json), history and projects
# are NOT shared: they belong to one account.
CPROF_SHARED_ITEMS=(
  CLAUDE.md AGENTS.md settings.json keybindings.json
  rules agents commands skills hooks output-styles plugins
)

# Path to the claude CLI. Apps launched from Finder get a short PATH,
# so look in the usual install places too.
claude_bin() {
  local c
  for c in "$(command -v claude 2>/dev/null)" "$HOME/.local/bin/claude" \
           /opt/homebrew/bin/claude /usr/local/bin/claude; do
    [[ -n "$c" && -x "$c" ]] && { printf '%s' "$c"; return 0; }
  done
  return 1
}

# Find Claude Desktop wherever it is installed. The menu bar app passes the
# exact location in $CPROF_DESKTOP_APP; on its own the CLI searches.
find_desktop_app() {
  local c
  for c in "${CPROF_DESKTOP_APP:-}" /Applications/Claude.app "$HOME/Applications/Claude.app"; do
    [[ -n "$c" && -d "$c" ]] && { printf '%s' "$c"; return 0; }
  done
  c="$(mdfind "kMDItemCFBundleIdentifier == '$CPROF_DESKTOP_BUNDLE_ID'" 2>/dev/null | head -n1)"
  [[ -n "$c" && -d "$c" ]] && { printf '%s' "$c"; return 0; }
  return 1
}

die()  { printf 'cprof: %s\n' "$*" >&2; exit 1; }
warn() { printf 'cprof: %s\n' "$*" >&2; }

validate_name() {
  [[ "$1" =~ $CPROF_NAME_RE ]] ||
    die "invalid profile name '$1' (use a-z, 0-9, '-', '_'; max 32 chars)"
}

profile_dir()  { printf '%s/%s' "$CPROF_HOME" "$1"; }

cli_dir() {
  if [[ "$1" == "default" ]]; then printf '%s' "$CPROF_DEFAULT_CLI_DIR"
  else printf '%s/cli' "$(profile_dir "$1")"; fi
}

# Empty output means "use the Desktop app's normal data folder".
desktop_dir() {
  [[ "$1" == "default" ]] || printf '%s/desktop' "$(profile_dir "$1")"
}

profile_exists() {
  [[ "$1" == "default" ]] || [[ -d "$(profile_dir "$1")" ]]
}

require_profile() {
  validate_name "$1"
  profile_exists "$1" || die "no profile '$1' (create it: cprof add $1)"
}

list_profiles() {
  printf 'default\n'
  [[ -d "$CPROF_HOME" ]] || return 0
  local d
  for d in "$CPROF_HOME"/*/; do
    [[ -d "$d" ]] && basename "$d"
  done
}

# Walk up from $1 (default: $PWD) and print the first .claude-profile
# value found. Prints nothing if there is none.
find_profile_file() {
  local dir="${1:-$PWD}" name
  while [[ -n "$dir" ]]; do
    if [[ -f "$dir/$CPROF_PROFILE_FILE" ]]; then
      name="$(head -n1 "$dir/$CPROF_PROFILE_FILE" | tr -d '[:space:]')"
      [[ -n "$name" ]] && { printf '%s' "$name"; return 0; }
    fi
    [[ "$dir" == "/" ]] && break
    dir="$(dirname "$dir")"
  done
}

# Decide which profile a command runs under.
# $1 = profile named on the command line (may be empty).
resolve_profile() {
  local explicit="$1" from_file
  if [[ -n "$explicit" ]]; then printf '%s' "$explicit"; return; fi
  if [[ -n "${CPROF_PROFILE:-}" ]]; then printf '%s' "$CPROF_PROFILE"; return; fi
  from_file="$(find_profile_file)"
  printf '%s' "${from_file:-default}"
}

# Print the pid of the Claude Desktop main process for a profile, if running.
# Tests supply a saved process list in the file $CPROF_PS_FILE.
desktop_pid() {
  local data app
  data="$(desktop_dir "$1")"
  app="$(find_desktop_app)" || return 0
  if [[ -n "${CPROF_PS_FILE:-}" ]]; then cat "$CPROF_PS_FILE"; else ps -axww -o pid=,command=; fi 2>/dev/null |
    awk -v exe="$app/Contents/MacOS/Claude" -v want="$data" '
      {
        pid = $1; sub(/^[ \t]*[0-9]+[ \t]+/, "")
        if (index($0, exe) != 1) next
        rest = substr($0, length(exe) + 1)
        if (rest != "" && substr(rest, 1, 1) != " ") next
        dir = ""; at = index(rest, " --user-data-dir=")
        if (at) {                       # value runs to the next " --flag" or the end,
          dir = substr(rest, at + 17)   # so folders with spaces still match
          cut = index(dir, " --"); if (cut) dir = substr(dir, 1, cut - 1)
        }
        if (dir == want) { print pid; exit }
      }'
}

# True if a Desktop instance for this profile is running.
desktop_running() { [[ -n "$(desktop_pid "$1")" ]]; }

# True if a profile's Claude Desktop has been signed in. Reads only the
# account id Desktop stores in config.json, never its tokens.
desktop_signed_in() {
  local data; data="$(desktop_dir "$1")"
  [[ -z "$data" ]] && data="${CPROF_DEFAULT_DESKTOP_DIR:-$HOME/Library/Application Support/Claude}"
  local id
  id="$(plutil -extract lastKnownAccountUuid raw -o - "$data/config.json" 2>/dev/null)" || return 1
  [[ -n "$id" ]]
}

# Each account can have an icon: the name of a monochrome system symbol
# such as "briefcase". Stored as one line of text; empty means none.
CPROF_ICON_RE='^[a-z0-9.]{1,48}$'
icon_file() {
  if [[ "$1" == "default" ]]; then printf '%s/.default-icon' "$CPROF_HOME"
  else printf '%s/icon' "$(profile_dir "$1")"; fi
}
profile_icon() {
  local icon=""
  [[ -f "$(icon_file "$1")" ]] && icon="$(head -n1 "$(icon_file "$1")" | tr -d '[:space:]')"
  [[ "$icon" =~ $CPROF_ICON_RE ]] && printf '%s' "$icon"
  return 0
}

json_str() { # JSON string: drop control characters, escape \ and "
  local s; s="$(printf '%s' "$1" | tr -d '\000-\037')"
  s="${s//\\/\\\\}"; s="${s//\"/\\\"}"; printf '"%s"' "$s"
}

# Link shared items from the default CLI dir into a profile's CLI dir.
# Existing real files are left alone, so a profile can override one.
link_shared() {
  local target src dst item
  target="$(cli_dir "$1")"
  for item in "${CPROF_SHARED_ITEMS[@]}"; do
    src="$CPROF_DEFAULT_CLI_DIR/$item"
    dst="$target/$item"
    [[ -e "$src" ]] || continue
    if [[ -L "$dst" ]]; then ln -sfn "$src" "$dst"
    elif [[ -e "$dst" ]]; then warn "$1: keeping own $item"
    else ln -s "$src" "$dst"; fi
  done
}

# Print the signed-in email for a profile's CLI, or nothing.
cli_account() {
  local json
  json="$(cli_dir "$1")/.claude.json"
  [[ "$1" == "default" ]] && json="${CPROF_DEFAULT_CLI_JSON:-$HOME/.claude.json}"
  plutil -extract oauthAccount.emailAddress raw -o - "$json" 2>/dev/null || true
}
