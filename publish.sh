#!/usr/bin/env bash
# Publish a release: put the notarized DMG on GitHub and point Homebrew at it.
#
#   ./release.sh              first: builds, signs and notarizes the DMG
#   ./publish.sh --dry-run    shows exactly what would happen, changes nothing
#   ./publish.sh              tags, creates the GitHub release, updates the tap
#
# After it finishes, people install with:
#   brew install --cask haffaz/tap/switchboard
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=release.env
source "$ROOT/release.env"
BUILD="$ROOT/build"
DMG="$BUILD/$APP_NAME-$VERSION.dmg"
TAG="v$VERSION"
CASK="$BUILD/switchboard.rb"
DRY=false
[[ "${1:-}" == "--dry-run" ]] && DRY=true
[[ $# -eq 0 || "${1:-}" == "--dry-run" ]] || { echo "usage: ./publish.sh [--dry-run]" >&2; exit 1; }

step() { printf '\033[1m==> %s\033[0m\n' "$*"; }
die()  { printf 'publish: %s\n' "$*" >&2; exit 1; }
# In a dry run a failed check is reported and the run continues, so one run
# lists everything that still needs doing.
check() { # check <message if it fails> <command...>
  local message="$1"; shift
  if "$@" >/dev/null 2>&1; then return 0; fi
  if $DRY; then printf '  not ready: %s\n' "$message"; PROBLEMS=$((PROBLEMS + 1)); else die "$message"; fi
}
PROBLEMS=0

tap_formula_name() { # Haffaz/homebrew-tap -> haffaz/tap
  local owner="${TAP_REPO%%/*}" repo="${TAP_REPO##*/}"
  printf '%s/%s' "$(tr '[:upper:]' '[:lower:]' <<<"$owner")" "${repo#homebrew-}"
}

render_cask() { # render_cask <sha256>
  mkdir -p "$BUILD"
  sed -e "s|@VERSION@|$VERSION|g" -e "s|@SHA256@|$1|g" -e "s|@REPO@|$GITHUB_REPO|g" \
      -e "s|@BUNDLE_ID@|$BUNDLE_ID|g" "$ROOT/packaging/switchboard.rb.template" > "$CASK"
  ruby -c "$CASK" >/dev/null || die "the generated cask is not valid Ruby"
}

is_public()      { [[ "$(gh repo view "$GITHUB_REPO" --json visibility -q .visibility)" == "PUBLIC" ]]; }
tag_is_free()    { ! git -C "$ROOT" rev-parse -q --verify "refs/tags/$TAG" >/dev/null &&
                   ! git -C "$ROOT" ls-remote --exit-code --tags origin "$TAG" >/dev/null 2>&1; }
tree_is_clean()  { [[ -z "$(git -C "$ROOT" status --porcelain)" ]]; }
on_main()        { [[ "$(git -C "$ROOT" branch --show-current)" == "main" ]]; }
in_sync()        { git -C "$ROOT" fetch -q origin main && [[ "$(git -C "$ROOT" rev-parse HEAD)" == "$(git -C "$ROOT" rev-parse origin/main)" ]]; }
dmg_notarized()  { xcrun stapler validate "$DMG"; }

step "Checking that $APP_NAME $VERSION is ready to publish"
check "GitHub CLI is not signed in (run: gh auth login)" gh auth status
check "not on the main branch" on_main
check "there are uncommitted changes" tree_is_clean
check "main is not in sync with GitHub (push or pull first)" in_sync
check "tag $TAG already exists; raise VERSION in release.env" tag_is_free
check "$GITHUB_REPO is private; Homebrew can only download from a public repository" is_public
check "no DMG at build/$(basename "$DMG") (run ./release.sh first)" test -f "$DMG"
check "the DMG is not notarized (run ./release.sh)" dmg_notarized

SHA="$(shasum -a 256 "$DMG" 2>/dev/null | cut -d' ' -f1 || true)"
render_cask "${SHA:-0000000000000000000000000000000000000000000000000000000000000000}"
INSTALL="brew install --cask $(tap_formula_name)/switchboard"

if $DRY; then
  step "Dry run: nothing was changed. A real run would:"
  cat <<PLAN
  1. tag this commit as $TAG and push the tag
  2. create GitHub release $TAG on $GITHUB_REPO with $(basename "$DMG")
  3. write Casks/switchboard.rb to $TAP_REPO (creating that public repository if needed)
  4. people then install with: $INSTALL

  The cask it would publish (build/switchboard.rb):
PLAN
  sed 's/^/    /' "$CASK"
  if [[ $PROBLEMS -eq 0 ]]; then echo "Everything is ready."; else echo "$PROBLEMS thing(s) not ready, listed above."; fi
  exit 0
fi

step "Tagging $TAG"
git -C "$ROOT" tag -a "$TAG" -m "$APP_NAME $VERSION"
git -C "$ROOT" push -q origin "$TAG"

step "Creating the GitHub release"
gh release create "$TAG" "$DMG" --repo "$GITHUB_REPO" --title "$APP_NAME $VERSION" --generate-notes

step "Updating the Homebrew tap"
gh repo view "$TAP_REPO" >/dev/null 2>&1 ||
  gh repo create "$TAP_REPO" --public --description "Homebrew tap for $APP_NAME" >/dev/null
TAP_DIR="$BUILD/tap"
rm -rf "$TAP_DIR"
gh repo clone "$TAP_REPO" "$TAP_DIR" -- -q
mkdir -p "$TAP_DIR/Casks"
cp "$CASK" "$TAP_DIR/Casks/switchboard.rb"
# Sign the tap's history as this project does, not with the machine-wide
# git identity, which may hold a private email address.
git -C "$TAP_DIR" config user.name "$(git -C "$ROOT" config user.name)"
git -C "$TAP_DIR" config user.email "$(git -C "$ROOT" config user.email)"
git -C "$TAP_DIR" add Casks/switchboard.rb
git -C "$TAP_DIR" commit -q -m "switchboard $VERSION"
git -C "$TAP_DIR" push -q origin HEAD

echo "Published. Install with: $INSTALL"
