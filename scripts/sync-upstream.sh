#!/bin/bash
#
# sync-upstream.sh - Sync Koshee Grafana fork with upstream Grafana releases
#
# Usage: ./scripts/sync-upstream.sh <upstream-tag>
# Example: ./scripts/sync-upstream.sh v11.2.0
#

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

UPSTREAM_TAG=${1:-}

# Branded files that will typically conflict
BRANDED_FILES=(
    "public/img/fav32.png"
    "public/img/apple-touch-icon.png"
    "public/img/grafana_icon.svg"
    "public/img/koshee_icon.svg"
    "public/img/logo_transparent_200x.png"
    "public/img/logo_transparent_400x.png"
    "pkg/setting/setting.go"
    "pkg/services/frontend/index.go"
    "pkg/services/frontend/index.html"
    "public/app/core/components/Branding/Branding.tsx"
)

usage() {
    echo "Usage: $0 <upstream-tag>"
    echo ""
    echo "Examples:"
    echo "  $0 v11.2.0     # Sync with specific release"
    echo "  $0 v11.2.1     # Sync with patch release"
    echo ""
    echo "Available upstream tags:"
    if git remote | grep -q upstream; then
        git tag -l 'v11.*' | sort -V | tail -10
    else
        echo "  (add upstream remote first to see tags)"
    fi
    exit 1
}

if [[ -z "$UPSTREAM_TAG" ]]; then
    usage
fi

echo -e "${GREEN}=== Koshee Grafana Upstream Sync ===${NC}"
echo ""

# Add upstream remote if not exists
if ! git remote | grep -q upstream; then
    echo -e "${YELLOW}Adding upstream remote...${NC}"
    git remote add upstream https://github.com/grafana/grafana.git
fi

# Fetch upstream
echo -e "${YELLOW}Fetching upstream...${NC}"
git fetch upstream --tags

# Verify tag exists
if ! git rev-parse "upstream/${UPSTREAM_TAG}" >/dev/null 2>&1; then
    echo -e "${RED}Error: Tag ${UPSTREAM_TAG} not found in upstream${NC}"
    echo ""
    echo "Available tags:"
    git tag -l 'v11.*' | sort -V | tail -10
    exit 1
fi

# Check for uncommitted changes
if ! git diff-index --quiet HEAD --; then
    echo -e "${RED}Error: You have uncommitted changes. Please commit or stash them first.${NC}"
    exit 1
fi

# Ensure we're on main
CURRENT_BRANCH=$(git branch --show-current)
if [[ "$CURRENT_BRANCH" != "main" ]]; then
    echo -e "${YELLOW}Switching to main branch...${NC}"
    git checkout main
fi

# Create sync branch
SYNC_BRANCH="sync/${UPSTREAM_TAG}"
if git show-ref --verify --quiet "refs/heads/${SYNC_BRANCH}"; then
    echo -e "${YELLOW}Branch ${SYNC_BRANCH} already exists. Deleting...${NC}"
    git branch -D "${SYNC_BRANCH}"
fi

echo -e "${YELLOW}Creating branch ${SYNC_BRANCH}...${NC}"
git checkout -b "${SYNC_BRANCH}"

# Attempt merge
echo -e "${YELLOW}Merging ${UPSTREAM_TAG}...${NC}"
echo ""

if git merge "upstream/${UPSTREAM_TAG}" --no-commit --no-ff 2>/dev/null; then
    echo -e "${GREEN}Merge completed without conflicts!${NC}"
    echo ""
    echo "Review the changes, then:"
    echo "  git diff --cached"
    echo "  git commit -m \"Sync with upstream ${UPSTREAM_TAG}\""
    echo "  git checkout main"
    echo "  git merge ${SYNC_BRANCH}"
else
    echo ""
    echo -e "${YELLOW}=== Merge conflicts detected ===${NC}"
    echo ""
    echo -e "${RED}Conflicting files:${NC}"
    git diff --name-only --diff-filter=U
    echo ""
    echo -e "${GREEN}Expected conflicts in branded files (keep Koshee version):${NC}"
    for file in "${BRANDED_FILES[@]}"; do
        if git diff --name-only --diff-filter=U | grep -q "^${file}$"; then
            echo "  - ${file} (CONFLICT - keep ours)"
        fi
    done
    echo ""
    echo -e "${YELLOW}Resolution commands:${NC}"
    echo ""
    echo "# For branded files, keep Koshee version:"
    for file in "${BRANDED_FILES[@]}"; do
        if git diff --name-only --diff-filter=U | grep -q "^${file}$"; then
            echo "git checkout --ours \"${file}\" && git add \"${file}\""
        fi
    done
    echo ""
    echo "# For other conflicts, review and resolve manually:"
    for file in $(git diff --name-only --diff-filter=U); do
        is_branded=false
        for branded in "${BRANDED_FILES[@]}"; do
            if [[ "$file" == "$branded" ]]; then
                is_branded=true
                break
            fi
        done
        if [[ "$is_branded" == "false" ]]; then
            echo "#   ${file}"
        fi
    done
    echo ""
    echo "# After resolving all conflicts:"
    echo "git add ."
    echo "git commit -m \"Sync with upstream ${UPSTREAM_TAG}\""
    echo ""
    echo "# Then merge to main:"
    echo "git checkout main"
    echo "git merge ${SYNC_BRANCH}"
fi

echo ""
echo -e "${GREEN}=== Post-sync checklist ===${NC}"
echo "[ ] Run tests: yarn test && go test ./pkg/..."
echo "[ ] Verify branding is preserved"
echo "[ ] Build Docker image: docker build -f Dockerfile.koshee ."
echo "[ ] Test locally: docker run -p 3000:3000 <image>"
echo "[ ] Create PR for review"
