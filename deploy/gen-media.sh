#!/usr/bin/env bash
# Генерация медиа через NVIDIA API. Запускается НА СЕРВЕРЕ (там есть интернет).
# Ключ читается из /etc/isihouse/nvidia.env (chmod 600), в репозиторий не попадает.
set -euo pipefail
source /etc/isihouse/nvidia.env      # NVIDIA_API_KEY=nvapi-...
OUT=${OUT:-/opt/isihouse-media}
mkdir -p "$OUT"

api() { # api <path> <json-file> <out-file>
  curl -sS -m 900 -X POST "https://integrate.api.nvidia.com/v1/$1" \
    -H "Authorization: Bearer $NVIDIA_API_KEY" \
    -H "Accept: application/json" \
    -H "Content-Type: application/json" \
    -d @"$2" -o "$3" -w "HTTP %{http_code}\n"
}

case "${1:-list}" in
  list)
    curl -sS -m 30 -H "Authorization: Bearer $NVIDIA_API_KEY" \
      https://integrate.api.nvidia.com/v1/models | python3 -c '
import json,sys
d=json.load(sys.stdin)
ids=[m["id"] for m in d.get("data",[])]
print(len(ids),"моделей всего")
kw=("video","cosmos","wan","ltx","svd","sana","stable-diffusion","flux","sdxl","image")
for i in sorted(ids):
    if any(k in i.lower() for k in kw): print(" ",i)
'
    ;;
  video)
    api "$2" "$3" "$OUT/video-response.json"
    ;;
  image)
    api "$2" "$3" "$OUT/image-response.json"
    ;;
esac
