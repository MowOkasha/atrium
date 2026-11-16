#!/usr/bin/env bash
# Builds Atrium, publishes a GitHub release and updates the Homebrew tap.
# Usage: scripts/release.sh 1.0.1
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:?usage: scripts/release.sh <version>}"
TAP_REPO="MowOkasha/homebrew-tap"

echo "$VERSION" > VERSION
git add VERSION && git commit -qm "Release $VERSION" || true
VERSION="$VERSION" ./scripts/build.sh
ZIP="build/Atrium-$VERSION.zip"
SHA=$(shasum -a 256 "$ZIP" | cut -d' ' -f1)

git tag -f "v$VERSION" && git push -q origin HEAD "v$VERSION" --force
gh release create "v$VERSION" "$ZIP" --title "Atrium $VERSION" --generate-notes

TAP_DIR=$(mktemp -d)
gh repo clone "$TAP_REPO" "$TAP_DIR" -- -q
git -C "$TAP_DIR" config user.email "$(git config user.email)"
git -C "$TAP_DIR" config user.name "$(git config user.name)"
mkdir -p "$TAP_DIR/Casks"
sed -e "s/__VERSION__/$VERSION/" -e "s/__SHA256__/$SHA/" Casks/atrium.rb.template > "$TAP_DIR/Casks/atrium.rb"
git -C "$TAP_DIR" add Casks/atrium.rb
git -C "$TAP_DIR" commit -qm "atrium $VERSION"
git -C "$TAP_DIR" push -q
rm -rf "$TAP_DIR"
echo "✓ Released Atrium $VERSION — brew upgrade --cask atrium"
