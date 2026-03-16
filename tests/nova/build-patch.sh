#!/bin/bash
# Build patch for nova tests.
# Workflow: fetch and reset branch to latest remote, then build patch from your changes.
# Run from bootstrap-openstack-k8s repo root:  ./tests/nova/build-patch.sh

set -e

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO_ROOT"

BRANCH=$(git branch --show-current)
echo "Branch: $BRANCH"
echo ""

# 1. Stash local changes (including untracked in tests/nova/)
echo "1. Stashing local changes in tests/nova/..."
git stash push -u -m "nova tests before build-patch" -- tests/nova/ 2>/dev/null || true
STASHED=$?

# 2. Fetch and reset to latest remote
echo "2. Fetching and resetting to origin/$BRANCH..."
git fetch origin
git reset --hard "origin/$BRANCH"

# 3. Re-apply stashed changes
if [ $STASHED -eq 0 ]; then
  echo "3. Re-applying your changes..."
  git stash pop 2>/dev/null || true
  if [ -f tests/nova/test-create-instance-keystone.sh ] && grep -q "<<<<<<<" tests/nova/test-create-instance-keystone.sh 2>/dev/null; then
    echo "   ⚠️  Conflict in test-create-instance-keystone.sh - resolve manually then run: git add tests/nova/ && git diff --cached HEAD > /root/patch-nova-tests.patch"
    exit 1
  fi
else
  echo "3. No stashed changes to re-apply. Make your edits, then run step 4 manually."
fi

# 4. Build patch
echo "4. Building patch..."
git add tests/nova/
git diff --cached HEAD > /root/patch-nova-tests.patch
git reset HEAD tests/nova/

echo ""
echo "✅ Patch written to /root/patch-nova-tests.patch ($(wc -l < /root/patch-nova-tests.patch) lines)"
echo "   Apply from repo root:  git apply /root/patch-nova-tests.patch"
