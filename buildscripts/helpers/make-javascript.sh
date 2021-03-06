#!/usr/bin/env bash
set -e

# Change directory to the project's root
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
cd "$DIR/../.."

# Change directory to assets
cd assets

# Install node packages
PACKAGE_JSON_CACHE="./node_modules/.package.json.last"
PACKAGE_LOCK_JSON_CACHE="./node_modules/.package-lock.json.last"

should_run_npm_install() {
    if [ ! -f "$PACKAGE_JSON_CACHE" ]; then
        echo "Missing cache for file: package.json"
        return
    fi

    if ! diff "./package.json" "$PACKAGE_JSON_CACHE" 2> /dev/null; then
        echo "Outdated cache for file: package.json"
        return
    fi

    if [ ! -f "./package-lock.json" ]; then
        echo "Missing file: package-lock.json"
        return
    fi

    if [ ! -f "$PACKAGE_LOCK_JSON_CACHE" ]; then
        echo "Missing cache for file: package-lock.json"
        return
    fi

    if ! diff "./package-lock.json" "$PACKAGE_LOCK_JSON_CACHE" 2> /dev/null; then
        echo "Outdated cache for file: package-lock.json"
        return
    fi

    false
}

if should_run_npm_install; then
    echo "Runing npm install..."
    npm install --no-audit
    cp "./package.json" "$PACKAGE_JSON_CACHE"
    cp "./package-lock.json" "$PACKAGE_LOCK_JSON_CACHE"
else
    echo "Skipping npm install..."
fi

# Compile first-party scripts
./node_modules/.bin/gulp scripts

# Compile third-party scripts
#./node_modules/.bin/gulp vendors:scripts
