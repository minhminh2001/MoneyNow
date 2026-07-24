#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FVM_VERSION="$(sed -n 's/.*"flutter"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$ROOT_DIR/.fvmrc")"

if [[ -z "${FVM_VERSION:-}" ]]; then
  echo "Khong doc duoc version Flutter tu .fvmrc"
  exit 1
fi

FLUTTER_BIN="$HOME/fvm/versions/$FVM_VERSION/bin/flutter"

if [[ ! -x "$FLUTTER_BIN" ]]; then
  echo "Khong tim thay Flutter tai: $FLUTTER_BIN"
  echo "Hay cai dung version truoc, hoac chay bang FVM."
  exit 1
fi

cd "$ROOT_DIR"

echo "Dang dung Flutter $FVM_VERSION"
"$FLUTTER_BIN" pub get
"$FLUTTER_BIN" run -d chrome --web-launch-url "/admin"
