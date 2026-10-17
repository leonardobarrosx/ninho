#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
sdk="${FLUTTER_ROOT:-$root/.sdk/flutter}"
if [[ ! -x "$sdk/bin/flutter" ]]; then
  git clone --depth 1 --branch 3.47.7 https://github.com/flutter/flutter.git "$sdk"
fi
export PATH="$sdk/bin:$PATH"
cd "$root/app"
flutter config --no-analytics
flutter pub get
if [[ "${NINHO_DEMO:-false}" == "true" ]]; then
  flutter build web --release
else
  : "${API_URL:?Set API_URL}"
  : "${SUPABASE_URL:?Set SUPABASE_URL}"
  : "${SUPABASE_PUBLISHABLE_KEY:?Set SUPABASE_PUBLISHABLE_KEY}"
  flutter build web --release --dart-define="API_URL=$API_URL" --dart-define="SUPABASE_URL=$SUPABASE_URL" --dart-define="SUPABASE_PUBLISHABLE_KEY=$SUPABASE_PUBLISHABLE_KEY"
fi
