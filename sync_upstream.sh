#!/usr/bin/env bash

set -e

echo "Fetching latest changes from upstream..."
git fetch upstream

echo "Merging upstream/main into current branch..."
git merge upstream/main

echo "Upstream sync completed!"
echo "Review changes, then commit and push when ready."
