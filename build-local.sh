#!/bin/bash
# Build one image on this host with the build args of the CI matrix (.github/workflows/build.yml), run the smoke
# test, and only then tag it as its pinned GHCR tag (ghcr.io/valhallamcio/yolks:<image>-<zulu>).
# For a Wings node that cannot pull the image: when the pull fails, Wings starts the server from a local image
# whose tag equals the panel image exactly.
# usage: [SMOKE_USER=uid:gid] ./build-local.sh <image>     e.g. SMOKE_USER=999:995 ./build-local.sh java_25_zulu_crac
set -euo pipefail
IMAGE=${1:?usage: build-local.sh <image>}
cd "$(dirname "$0")"
row=$(awk -v img="$IMAGE" '
  /^ *- image: / { on = ($3 == img) }
  on && /^ *(base|zulu|expect|crac): / { k = $1; sub(/:$/, "", k); v = $0; sub(/^ *[a-z]+: */, "", v); gsub(/"/, "", v); f[k] = v }
  END { if (f["base"] != "") print f["base"] "|" f["zulu"] "|" f["expect"] "|" f["crac"] }
' .github/workflows/build.yml)
[ -n "$row" ] || { echo "no matrix entry for $IMAGE in .github/workflows/build.yml" >&2; exit 2; }
IFS='|' read -r BASE ZULU EXPECT CRAC <<<"$row"
TAG=ghcr.io/valhallamcio/yolks:$IMAGE-$ZULU
TEST=local/yolks:$IMAGE-$ZULU
echo "build $IMAGE: base $BASE, expect '$EXPECT', crac '${CRAC:-no}'"
nice -n 19 ionice -c3 docker build -q --build-arg ZULU_IMAGE="$BASE" --build-arg ZULU_EXPECT="$EXPECT" -t "$TEST" .
bash test/smoke.sh "$TEST" "$EXPECT" "$CRAC"
docker tag "$TEST" "$TAG"
docker image rm -f "$TEST" >/dev/null
echo "tagged $TAG $(docker image inspect -f '{{.Id}}' "$TAG")"
