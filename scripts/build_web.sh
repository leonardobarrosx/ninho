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
# The site serves Flutter's CanvasKit itself instead of loading it from
# Google's CDN (www.gstatic.com).
if [[ "${NINHO_DEMO:-false}" == "true" ]]; then
  flutter build web --release --no-web-resources-cdn
else
  : "${API_URL:?Set API_URL}"
  : "${SUPABASE_URL:?Set SUPABASE_URL}"
  : "${SUPABASE_PUBLISHABLE_KEY:?Set SUPABASE_PUBLISHABLE_KEY}"
  # The privacy policy must name who controls the data and how to reach them.
  : "${PRIVACY_CONTROLLER:?Set PRIVACY_CONTROLLER}"
  : "${PRIVACY_EMAIL:?Set PRIVACY_EMAIL}"
  flutter build web --release --no-web-resources-cdn --dart-define="API_URL=$API_URL" --dart-define="SUPABASE_URL=$SUPABASE_URL" --dart-define="SUPABASE_PUBLISHABLE_KEY=$SUPABASE_PUBLISHABLE_KEY"
fi

# Fill the controller and contact into the privacy and account deletion pages: HTML-escape the value,
# then escape it for the sed replacement below. (Bash 5.2 expands & in ${s//x/y}, so sed does both.)
html() {
  printf '%s' "$1" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' -e 's/"/\&quot;/g' -e 's/[|&\\]/\\&/g'
}
controller="$(html "${PRIVACY_CONTROLLER:-o responsável pelo Ninho (a definir)}")"
email="$(html "${PRIVACY_EMAIL:-contato a definir}")"
sed -i -e "s|__RESPONSAVEL__|$controller|g" -e "s|__EMAIL__|$email|g" build/web/privacidade.html build/web/excluir-conta.html

# AdMob checks app-ads.txt on the developer website listed on Google Play.
if [[ -n "${ADMOB_PUBLISHER_ID:-}" ]]; then
  [[ "$ADMOB_PUBLISHER_ID" =~ ^pub-[0-9]{16}$ ]] || { echo "ADMOB_PUBLISHER_ID must look like pub-0000000000000000" >&2; exit 1; }
  printf 'google.com, %s, DIRECT, f08c47fec0942fa0\n' "$ADMOB_PUBLISHER_ID" > build/web/app-ads.txt
fi
