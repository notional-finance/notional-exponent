#!/bin/bash
#
# Setup script for git hooks
# This script sets up the pre-commit hook for the project
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║                  🔧 Setting up Git Hooks                    ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Check if we're in a git repository
if ! git rev-parse --git-dir > /dev/null 2>&1; then
    echo -e "${RED}❌ Error: Not in a git repository${NC}"
    echo "Please run this script from the root of your git repository."
    exit 1
fi

# Check if yarn is available
if ! command -v yarn &> /dev/null; then
    echo -e "${RED}❌ Error: yarn is not installed or not in PATH${NC}"
    echo "Please install yarn and try again."
    exit 1
fi

# Create hooks directory if it doesn't exist
HOOKS_DIR=".git/hooks"
if [ ! -d "$HOOKS_DIR" ]; then
    echo -e "${YELLOW}📁 Creating hooks directory...${NC}"
    mkdir -p "$HOOKS_DIR"
fi

# Copy the pre-commit hook
HOOK_FILE="$HOOKS_DIR/pre-commit"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ -f "$SCRIPT_DIR/.git/hooks/pre-commit" ]; then
    echo -e "${YELLOW}📋 Copying pre-commit hook...${NC}"
    cp "$SCRIPT_DIR/.git/hooks/pre-commit" "$HOOK_FILE"
    chmod +x "$HOOK_FILE"
    echo -e "${GREEN}✅ Pre-commit hook installed successfully!${NC}"
else
    echo -e "${RED}❌ Error: Pre-commit hook template not found${NC}"
    echo "Please make sure the pre-commit hook exists in .git/hooks/"
    exit 1
fi

echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║                    ✅ Setup Complete!                       ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${YELLOW}📝 What this hook does:${NC}"
echo "  • Runs 'yarn lint' before each commit"
echo "  • Checks Solidity code formatting (forge fmt)"
echo "  • Runs Solhint linting on .sol files"
echo "  • Checks Prettier formatting on non-Solidity files"
echo ""
echo -e "${YELLOW}🚀 The hook will now run automatically on every commit!${NC}"
echo ""
echo -e "${YELLOW}💡 To test the hook manually:${NC}"
echo "  .git/hooks/pre-commit"
echo ""
echo -e "${YELLOW}💡 To skip the hook (not recommended):${NC}"
echo "  git commit --no-verify -m \"your commit message\""
echo ""
echo -e "${YELLOW}💡 To remove the hook:${NC}"
echo "  rm .git/hooks/pre-commit"
echo ""
