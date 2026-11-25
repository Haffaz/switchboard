#!/usr/bin/env bash
# Plain-bash tests for cprof. No apps are launched; all paths are temporary.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CPROF="$ROOT/bin/cprof"
PASS=0; FAIL=0

setup() {
  SANDBOX="$(mktemp -d "${TMPDIR:-/tmp}/cprof-test.XXXXXX")"
  export CPROF_HOME="$SANDBOX/profiles"
  export CPROF_DEFAULT_CLI_DIR="$SANDBOX/dot-claude"
  unset CPROF_PROFILE CLAUDE_CONFIG_DIR CPROF_PS_FILE CPROF_DEFAULT_CLI_JSON CPROF_DEFAULT_DESKTOP_DIR
  export CPROF_DESKTOP_APP="$SANDBOX/Apps/Claude.app"; mkdir -p "$CPROF_DESKTOP_APP"
  mkdir -p "$CPROF_DEFAULT_CLI_DIR/rules" "$SANDBOX/repo/sub"
  echo "# shared" > "$CPROF_DEFAULT_CLI_DIR/CLAUDE.md"
}
teardown() { cd "$ROOT" || exit 1; rm -rf "$SANDBOX"; }

check() { # check <description> <expected> <actual>
  if [[ "$2" == "$3" ]]; then PASS=$((PASS+1)); printf '  ok   %s\n' "$1"
  else FAIL=$((FAIL+1)); printf '  FAIL %s\n       want: %q\n       got:  %q\n' "$1" "$2" "$3"; fi
}

run_test() { setup; "$1"; teardown; }

t_add_creates_layout() {
  "$CPROF" add work >/dev/null
  check "cli dir exists"     yes "$([[ -d $CPROF_HOME/work/cli ]] && echo yes)"
  check "desktop dir exists" yes "$([[ -d $CPROF_HOME/work/desktop ]] && echo yes)"
  check "CLAUDE.md linked"   "$CPROF_DEFAULT_CLI_DIR/CLAUDE.md" "$(readlink "$CPROF_HOME/work/cli/CLAUDE.md")"
  check "rules linked"       "$CPROF_DEFAULT_CLI_DIR/rules" "$(readlink "$CPROF_HOME/work/cli/rules")"
  check "auth not shared"    no "$([[ -e $CPROF_HOME/work/cli/.claude.json ]] && echo yes || echo no)"
}

t_add_rejects_bad_names() {
  "$CPROF" add 'Bad Name' 2>/dev/null; check "space rejected" 1 "$?"
  "$CPROF" add '../x' 2>/dev/null;     check "path rejected"  1 "$?"
  "$CPROF" add default 2>/dev/null;    check "default rejected" 1 "$?"
  "$CPROF" add work >/dev/null; "$CPROF" add work 2>/dev/null
  check "duplicate rejected" 1 "$?"
}

t_link_keeps_override() {
  "$CPROF" add work >/dev/null
  rm "$CPROF_HOME/work/cli/CLAUDE.md"; echo "# own" > "$CPROF_HOME/work/cli/CLAUDE.md"
  "$CPROF" link work 2>/dev/null
  check "own file kept" "# own" "$(cat "$CPROF_HOME/work/cli/CLAUDE.md")"
}

t_env_output() {
  "$CPROF" add work >/dev/null
  check "env work"    "export CPROF_PROFILE=work
export CLAUDE_CONFIG_DIR=$(printf %q "$CPROF_HOME/work/cli")" "$("$CPROF" env work)"
  check "env default" "export CPROF_PROFILE=default
unset CLAUDE_CONFIG_DIR" "$("$CPROF" env default)"
}

t_resolve_order() {
  "$CPROF" add work >/dev/null; "$CPROF" add personal >/dev/null
  cd "$SANDBOX/repo/sub" || return
  check "nothing set -> default" default "$("$CPROF" which)"
  echo personal > "$SANDBOX/repo/.claude-profile"
  check "file in parent folder"  personal "$("$CPROF" which)"
  check "env beats file"         work "$(CPROF_PROFILE=work "$CPROF" which)"
  check "explicit beats env"     personal "$(CPROF_PROFILE=work "$CPROF" env personal | head -1 | cut -d= -f2)"
}

t_list_json() {
  export CPROF_DEFAULT_CLI_JSON="$SANDBOX/none.json" CPROF_DEFAULT_DESKTOP_DIR="$SANDBOX/none"
  "$CPROF" add work >/dev/null
  echo '{"oauthAccount":{"emailAddress":"me@work.example"}}' > "$CPROF_HOME/work/cli/.claude.json"
  local out; out="$("$CPROF" list --json)"
  check "json parses" ok "$(plutil -convert json -o /dev/null - <<<"$out" 2>/dev/null && echo ok)"
  check "work email" "me@work.example" "$(plutil -extract 1.email raw -o - - <<<"$out")"
  check "default unsigned" "" "$(plutil -extract 0.email raw -o - - <<<"$out")"
  check "desktop not signed in" false "$(plutil -extract 1.desktopSignedIn raw -o - - <<<"$out")"
  echo '{"lastKnownAccountUuid":"abc"}' > "$CPROF_HOME/work/desktop/config.json"
  out="$("$CPROF" list --json)"
  check "desktop signed in" true "$(plutil -extract 1.desktopSignedIn raw -o - - <<<"$out")"
  check "text fallback" "(not signed in)" "$("$CPROF" list | awk '$2=="default"{print $3" "$4" "$5}')"
}

t_rm_yes() {
  "$CPROF" add work >/dev/null
  "$CPROF" rm work --yes >/dev/null
  check "profile removed" no "$([[ -d $CPROF_HOME/work ]] && echo yes || echo no)"
}

t_desktop_pid() {
  "$CPROF" add work >/dev/null; "$CPROF" add idle >/dev/null
  local exe="$CPROF_DESKTOP_APP/Contents/MacOS/Claude"
  export CPROF_PS_FILE="$SANDBOX/ps.txt"
  cat > "$CPROF_PS_FILE" <<EOF
  101 $exe
  102 $CPROF_DESKTOP_APP/Contents/Frameworks/Claude Helper.app/Contents/MacOS/Claude Helper --user-data-dir=$CPROF_HOME/work/desktop
  103 $exe --user-data-dir=$CPROF_HOME/work/desktop --some-flag
  104 ${exe}Other --user-data-dir=$CPROF_HOME/work/desktop
EOF
  check "default pid" 101 "$("$CPROF" desktop-pid default)"
  check "work pid"    103 "$("$CPROF" desktop-pid work)"
  check "not running" ""  "$("$CPROF" desktop-pid idle)"
}

t_desktop_pid_folder_with_space() {
  export CPROF_HOME="$SANDBOX/my profiles"
  "$CPROF" add work >/dev/null
  export CPROF_PS_FILE="$SANDBOX/ps.txt"
  echo "  201 $CPROF_DESKTOP_APP/Contents/MacOS/Claude --user-data-dir=$CPROF_HOME/work/desktop" > "$CPROF_PS_FILE"
  check "matches despite space" 201 "$("$CPROF" desktop-pid work)"
}

t_json_strips_control_chars() {
  "$CPROF" add work >/dev/null
  printf '{"oauthAccount":{"emailAddress":"a\\tb@x.example"}}' > "$CPROF_HOME/work/cli/.claude.json"
  local out; out="$("$CPROF" list --json)"
  check "still valid json" ok "$(plutil -convert json -o /dev/null - <<<"$out" 2>/dev/null && echo ok)"
  check "desktopDir present" "$CPROF_HOME/work/desktop" "$(plutil -extract 1.desktopDir raw -o - - <<<"$out")"
}

t_icons() {
  "$CPROF" add work >/dev/null
  "$CPROF" icon work briefcase.fill >/dev/null
  "$CPROF" icon default house >/dev/null
  local out; out="$("$CPROF" list --json)"
  check "default icon" house "$(plutil -extract 0.icon raw -o - - <<<"$out")"
  check "work icon" briefcase.fill "$(plutil -extract 1.icon raw -o - - <<<"$out")"
  "$CPROF" icon work 'bad icon; rm -rf' 2>/dev/null; check "bad icon rejected" 1 "$?"
  "$CPROF" icon work >/dev/null
  check "icon cleared" "" "$(plutil -extract 1.icon raw -o - - <<<"$("$CPROF" list --json)")"
  check "default is not listed twice" 2 "$("$CPROF" list | wc -l | tr -d ' ')"
}

t_unknown_profile_fails() {
  "$CPROF" env ghost 2>/dev/null; check "unknown profile exits 1" 1 "$?"
}

for t in $(declare -F | awk '{print $3}' | grep '^t_'); do
  echo "$t"; run_test "$t"
done
printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[[ $FAIL -eq 0 ]]
