#!/bin/bash
# Scripts/generate-release-notes.sh
# Generate release notes from git commits

VERSION=$1
if [ -z "$VERSION" ]; then
    echo "Usage: $0 <version>"
    echo "Example: $0 v1.0.0"
    exit 1
fi

# Remove 'v' prefix if present for display
DISPLAY_VERSION=${VERSION#v}

# Get previous tag
PREVIOUS_TAG=$(git describe --tags --abbrev=0 HEAD~1 2>/dev/null || echo "")

OUTPUT="RELEASE_NOTES.md"

echo "Generating release notes for v$DISPLAY_VERSION..."
echo "Previous tag: ${PREVIOUS_TAG:-'(none - first release)' }"

echo "# Riptide v$DISPLAY_VERSION" > $OUTPUT
echo "" >> $OUTPUT
echo "**Release Date:** $(date +%Y-%m-%d)" >> $OUTPUT
echo "" >> $OUTPUT

# Helper function to get commits
git_log() {
    local pattern=$1
    if [ -z "$PREVIOUS_TAG" ]; then
        git log --pretty=format:"- %s (%h)" --grep="^$pattern" 2>/dev/null || true
    else
        git log $PREVIOUS_TAG..HEAD --pretty=format:"- %s (%h)" --grep="^$pattern" 2>/dev/null || true
    fi
}

# Helper function to get other commits (non-conventional)
git_log_other() {
    if [ -z "$PREVIOUS_TAG" ]; then
        git log --pretty=format:"- %s (%h)" 2>/dev/null | grep -v "^feat:" | grep -v "^fix:" | grep -v "^refactor:" | grep -v "^perf:" | grep -v "^improve:" | grep -v "^chore:" | grep -v "^docs:" | grep -v "^ci:" | grep -v "^build:" | grep -v "^test:" || true
    else
        git log $PREVIOUS_TAG..HEAD --pretty=format:"- %s (%h)" 2>/dev/null | grep -v "^feat:" | grep -v "^fix:" | grep -v "^refactor:" | grep -v "^perf:" | grep -v "^improve:" | grep -v "^chore:" | grep -v "^docs:" | grep -v "^ci:" | grep -v "^build:" | grep -v "^test:" || true
    fi
}

# Features
echo "## ✨ New Features" >> $OUTPUT
FEATURES=$(git_log "feat")
if [ -n "$FEATURES" ]; then
    echo "$FEATURES" >> $OUTPUT
else
    echo "- No new features in this release" >> $OUTPUT
fi
echo "" >> $OUTPUT
echo "" >> $OUTPUT

# Bug fixes
echo "## 🐛 Bug Fixes" >> $OUTPUT
FIXES=$(git_log "fix")
if [ -n "$FIXES" ]; then
    echo "$FIXES" >> $OUTPUT
else
    echo "- No bug fixes in this release" >> $OUTPUT
fi
echo "" >> $OUTPUT
echo "" >> $OUTPUT

# Improvements (refactor, perf, improve)
echo "## 📈 Improvements" >> $OUTPUT
IMPROVEMENTS=$(git_log "refactor\|^perf\|^improve")
if [ -n "$IMPROVEMENTS" ]; then
    echo "$IMPROVEMENTS" >> $OUTPUT
else
    echo "- No improvements in this release" >> $OUTPUT
fi
echo "" >> $OUTPUT
echo "" >> $OUTPUT

# Other changes (chore, docs, ci, build)
echo "## 📦 Other Changes" >> $OUTPUT
OTHERS=$(git_log "chore\|^docs\|^ci\|^build\|^test")
if [ -n "$OTHERS" ]; then
    echo "$OTHERS" >> $OUTPUT
else
    echo "- No other changes in this release" >> $OUTPUT
fi
echo "" >> $OUTPUT
echo "" >> $OUTPUT

# Other non-conventional commits
OTHER_COMMITS=$(git_log_other)
if [ -n "$OTHER_COMMITS" ]; then
    echo "## 📝 Additional Changes" >> $OUTPUT
    echo "$OTHER_COMMITS" >> $OUTPUT
    echo "" >> $OUTPUT
    echo "" >> $OUTPUT
fi

# Assets placeholder
echo "## 📥 Assets" >> $OUTPUT
echo "" >> $OUTPUT
echo "| Platform | File |" >> $OUTPUT
echo "|----------|------|" >> $OUTPUT
echo "| macOS Universal | Riptide-macos-universal.zip |" >> $OUTPUT
echo "| macOS DMG | Riptide.dmg |" >> $OUTPUT
echo "| Windows x64 | Riptide-windows-x64.msi |" >> $OUTPUT
echo "" >> $OUTPUT

# Checksums placeholder - will be populated by CI
echo "## 🔐 Checksums" >> $OUTPUT
echo "" >> $OUTPUT
echo "| File | SHA256 |" >> $OUTPUT
echo "|------|--------|" >> $OUTPUT
echo "| Riptide-macos-universal.zip | (will be populated by CI) |" >> $OUTPUT
echo "| Riptide.dmg | (will be populated by CI) |" >> $OUTPUT
echo "| Riptide-windows-x64.msi | (will be populated by CI) |" >> $OUTPUT
echo "" >> $OUTPUT

# Installation notes
echo "## 🚀 Installation" >> $OUTPUT
echo "" >> $OUTPUT
echo "### macOS" >> $OUTPUT
echo "1. Download the DMG or ZIP file" >> $OUTPUT
echo "2. Open the DMG and drag Riptide to Applications, or extract the ZIP" >> $OUTPUT
echo "3. On first launch, you may need to right-click and select 'Open' to bypass Gatekeeper" >> $OUTPUT
echo "" >> $OUTPUT
echo "### Windows" >> $OUTPUT
echo "1. Download the MSI installer" >> $OUTPUT
echo "2. Run the installer and follow the prompts" >> $OUTPUT
echo "3. Launch Riptide from the Start menu or desktop shortcut" >> $OUTPUT
echo "" >> $OUTPUT

# Requirements
echo "## 📋 System Requirements" >> $OUTPUT
echo "" >> $OUTPUT
echo "- **macOS**: macOS 14.0+ (Sonoma)" >> $OUTPUT
echo "- **Windows**: Windows 10/11 64-bit" >> $OUTPUT
echo "" >> $OUTPUT

echo "Release notes generated: $OUTPUT"
