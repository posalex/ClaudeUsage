#!/usr/bin/env bash
set -euo pipefail

VERSION="${1:?Usage: scripts/release.sh <version>}"
TAG="v${VERSION}"
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ARCHIVE_DIR="$ROOT_DIR/dist"
ARCHIVE_PATH="$ARCHIVE_DIR/ClaudeUsage-${VERSION}.zip"

[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || {
  echo "Version must use the form major.minor.patch (for example: 1.1.1)." >&2
  exit 2
}

cd "$ROOT_DIR"

test "$(git branch --show-current)" = "main" || {
  echo "Release must run from main." >&2
  exit 1
}
test -z "$(git status --porcelain)" || {
  echo "Working tree is not clean. Commit the release changes first." >&2
  exit 1
}
test -z "$(git tag -l "$TAG")" || {
  echo "Tag $TAG already exists." >&2
  exit 1
}
test ! -e "$ARCHIVE_PATH" || {
  echo "Archive already exists: $ARCHIVE_PATH" >&2
  exit 1
}

echo "==> Generating the Xcode project"
xcodegen generate

echo "==> Building ClaudeUsage $VERSION for Apple Silicon"
xcodebuild \
  -project ClaudeUsage.xcodeproj \
  -scheme ClaudeUsage \
  -configuration Release \
  -derivedDataPath build \
  MARKETING_VERSION="$VERSION" \
  CURRENT_PROJECT_VERSION="$(git rev-list --count HEAD)" \
  ARCHS=arm64 \
  ONLY_ACTIVE_ARCH=YES \
  CODE_SIGN_IDENTITY=- \
  CODE_SIGNING_ALLOWED=NO \
  build

echo "==> Packaging local release archive"
mkdir -p "$ARCHIVE_DIR"
ditto -c -k --keepParent \
  build/Build/Products/Release/ClaudeUsage.app \
  "$ARCHIVE_PATH"

echo "==> Pushing main and $TAG"
git push origin main
git tag -a "$TAG" -m "Release $VERSION"
git push origin "$TAG"

cat <<EOF
Release workflow started for $TAG.
Local archive: $ARCHIVE_PATH
When the GitHub asset is ready, publish the Cask with:
  ../homebrew-tap/scripts/publish-claude-usage-cask.sh $VERSION
EOF
