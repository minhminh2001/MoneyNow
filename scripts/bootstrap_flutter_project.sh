#!/usr/bin/env bash
set -e

if ! command -v flutter >/dev/null 2>&1; then
  echo "Flutter chua duoc cai dat trong PATH."
  exit 1
fi

TMP_DIR="$(mktemp -d)"
GEN_DIR="$TMP_DIR/generated_app"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

flutter create "$GEN_DIR" \
  --platforms=android,ios,web \
  --project-name=loan_app_firebase_mvp \
  --org=com.example.loanappfirebase

rm -rf android ios web .metadata
cp -R "$GEN_DIR/android" ./android
cp -R "$GEN_DIR/ios" ./ios
cp -R "$GEN_DIR/web" ./web
cp "$GEN_DIR/.metadata" ./.metadata

flutter pub get

echo "Da bootstrap xong project Flutter."
echo "Tiep theo hay chay: flutterfire configure"
