#!/usr/bin/env bash
set -euo pipefail

# This script requires code-server and vscode to be built with
# matching MINIFY.

# RELEASE_PATH is the destination directory for the release from the root.
# Defaults to release
RELEASE_PATH="${RELEASE_PATH-release}"

# PACKAGE_NODE controls whether node and node_modules are packaged into the release.
# Disabled by default.
PACKAGE_NODE="${PACKAGE_NODE-}"

# MINIFY controls whether minified vscode is bundled and whether
# any included node_modules are pruned for production.
MINIFY="${MINIFY-true}"

main() {
  cd "$(dirname "${0}")/.."
  source ./ci/lib.sh

  mkdir -p "$RELEASE_PATH"

  bundle_code_server
  bundle_vscode

  rsync release_README.md "$RELEASE_PATH"
  rsync LICENSE.txt "$RELEASE_PATH"
  rsync ./lib/vscode/ThirdPartyNotices.txt "$RELEASE_PATH"

  if [[ $PACKAGE_NODE ]]; then
    rsync "$(command -v node)" ./build
    rsync ./ci/code-server.sh "$RELEASE_PATH/code-server"
  else
    rm -Rf "$RELEASE_PATH/node"
    rm -Rf "$RELEASE_PATH/code-server.sh"
  fi
}

rsync() {
  command rsync -a --del "$@"
}

bundle_code_server() {
  rsync out dist "$RELEASE_PATH"

  # For source maps and images.
  mkdir -p "$RELEASE_PATH/src/browser/media"
  mkdir -p "$RELEASE_PATH/src/browser/pages"
  rsync src/browser/media "$RELEASE_PATH/src/browser/media"
  rsync src/browser/pages/*.html "$RELEASE_PATH/src/browser/pages"

  rsync yarn.lock "$RELEASE_PATH"

  if [[ $PACKAGE_NODE ]]; then
    rsync node_modules "$RELEASE_PATH"
  else
    rm -Rf "$RELEASE_PATH/node_modules"
  fi

  # Adds the commit to package.json
  jq --slurp '.[0] * .[1]' package.json <(
    cat << EOF
  {
    "commit": "$(git rev-parse HEAD)",
    "scripts": {
      "install": "cd lib/vscode && yarn --production"
    }
  }
EOF
  ) > "$RELEASE_PATH/package.json"

  if [[ $PACKAGE_NODE && $MINIFY ]]; then
    pushd "$RELEASE_PATH"
    yarn --production
    popd
  fi
}

bundle_vscode() {
  local VSCODE_SRC_PATH="lib/vscode"
  local VSCODE_OUT_PATH="$RELEASE_PATH/lib/vscode"

  mkdir -p "$VSCODE_OUT_PATH"
  rsync "$VSCODE_SRC_PATH/out-vscode${MINIFY+-min}/" "$VSCODE_OUT_PATH/out"
  rsync "$VSCODE_SRC_PATH/.build/extensions/" "$VSCODE_OUT_PATH/extensions"

  mkdir -p "$VSCODE_OUT_PATH/resources/linux"
  rsync "$VSCODE_SRC_PATH/resources/linux/code.png" "$VSCODE_OUT_PATH/resources/linux/code.png"

  rsync "$VSCODE_SRC_PATH/yarn.lock" "$VSCODE_OUT_PATH"

  if [[ $PACKAGE_NODE ]]; then
    rsync "$VSCODE_SRC_PATH/node_modules" "$VSCODE_OUT_PATH"
  else
    rm -Rf "$VSCODE_OUT_PATH/node_modules"
  fi

  # Adds the commit and date to product.json
  jq --slurp '.[0] * .[1]' "$VSCODE_SRC_PATH/product.json" <(
    cat << EOF
  {
    "commit": "$(git rev-parse HEAD)",
    "date": $(jq -n 'now | todate')
  }
EOF
  ) > "$VSCODE_OUT_PATH/product.json"

  # We remove the scripts field so that later on we can run
  # yarn to fetch node_modules if necessary without build scripts
  # being ran.
  jq 'del(.scripts)' < "$VSCODE_SRC_PATH/package.json" > "$VSCODE_OUT_PATH/package.json"

  if [[ $PACKAGE_NODE && $MINIFY ]]; then
    pushd "$VSCODE_OUT_PATH"
    yarn --production
    popd
  fi
}

main "$@"
