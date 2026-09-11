#!/bin/sh
set -eu

cd "$(dirname "$0")"

apps=${*:-shire moria rivendell}

kubectl --context stark apply -f .

for app in $apps; do
  docker build --platform linux/arm64 -t "julianone/$app:latest" --push "../$app"
  kubectl --context stark rollout restart "deploy/$app"
  kubectl --context stark rollout status "deploy/$app"
done
