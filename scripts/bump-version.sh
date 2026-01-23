#!/usr/bin/env bash
# Script to bump version locally
# Usage: ./scripts/bump-version.sh [major|minor|patch] [prerelease]

set -euo pipefail

BUMP_TYPE="${1:-patch}"
PRERELEASE="${2:-}"

# Read current version
CURRENT=$(cat VERSION | tr -d '[:space:]')
echo "Current version: $CURRENT"

# Parse version (handle prerelease suffix)
BASE_VERSION="${CURRENT%%-*}"
IFS='.' read -r MAJOR MINOR PATCH <<<"$BASE_VERSION"

# Calculate new version
case "$BUMP_TYPE" in
major)
  MAJOR=$((MAJOR + 1))
  MINOR=0
  PATCH=0
  ;;
minor)
  MINOR=$((MINOR + 1))
  PATCH=0
  ;;
patch)
  PATCH=$((PATCH + 1))
  ;;
*)
  echo "Usage: $0 [major|minor|patch] [prerelease]"
  exit 1
  ;;
esac

NEW_VERSION="${MAJOR}.${MINOR}.${PATCH}"

# Add prerelease if specified
if [ -n "$PRERELEASE" ]; then
  NEW_VERSION="${NEW_VERSION}-${PRERELEASE}"
fi

echo "New version: $NEW_VERSION"

# Update VERSION file
echo "$NEW_VERSION" >VERSION

# Update changelog with date
DATE=$(date +%Y-%m-%d)
if [ -f "docs/sphinx/changelog.md" ]; then
  sed -i.bak "s/## \[Unreleased\]/## [Unreleased]\n\n## [$NEW_VERSION] - $DATE/" docs/sphinx/changelog.md
  rm -f docs/sphinx/changelog.md.bak
  echo "Updated changelog"
fi

echo ""
echo "Version bumped to $NEW_VERSION"
echo ""
echo "Next steps:"
echo "  1. Review changes: git diff"
echo "  2. Commit: git commit -am 'chore: bump version to $NEW_VERSION'"
echo "  3. Tag: git tag v$NEW_VERSION"
echo "  4. Push: git push && git push --tags"
