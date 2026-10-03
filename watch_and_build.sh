#!/usr/bin/env bash
# watch_and_build.sh – Rebuild the SoundBarBoost app whenever source files change.
# Requires `fswatch` (install via: brew install fswatch) or `entr` as an alternative.
# Usage: ./watch_and_build.sh
# The script runs indefinitely; press Ctrl+C to stop.

# Directory to watch (project root)
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Ensure we are in the project root
cd "$PROJECT_ROOT"

# Check for fswatch, fall back to entr
if command -v fswatch >/dev/null 2>&1; then
    echo "[watch_and_build] Using fswatch – press Ctrl+C to stop."
    # Watch all Swift source files and Package.swift
    fswatch -0 -e "\.git" -e "\.build" -i ".*\.swift$" -i "Package\.swift" | \
    while IFS= read -r -d "" event; do
        echo "[watch_and_build] Change detected: $event"
        echo "[watch_and_build] Rebuilding..."
        swift build
    done
elif command -v entr >/dev/null 2>&1; then
    echo "[watch_and_build] Using entr – press Ctrl+C to stop."
    # Find all Swift files and Package.swift, feed to entr
    find . -type f \( -name "*.swift" -o -name "Package.swift" \) | \
    entr -c swift build
else
    echo "[watch_and_build] Error: Neither 'fswatch' nor 'entr' is installed. Install one of them (e.g., brew install fswatch) and rerun the script."
    exit 1
fi
