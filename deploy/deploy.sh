#!/usr/bin/env bash
# isi.house v2 — развёртывание статического сайта + API заявок.
# Запускать на сервере от root:  bash deploy.sh
set -euo pipefail

REPO="${REPO:-}"                 # git-URL репозитория (обязателен при первом запуске)
SITE_DIR=/var/www/isihouse
SRC_DIR=/opt/isihouse-src
LEADS_DIR=/opt/isi-leads
ENV_DIR=/etc/isihouse
BACKUP_DIR=/opt/backups

say(){ printf '\n\033[1m==> %s\033[0m\n' "$1"; }

say "1. Пакеты"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq nginx python3 git curl >/dev/null

say "2. Сохраняем секреты и заявки старой версии"
mkdir -p "$ENV_DIR" "$BACKUP_DIR" "$LEADS_DIR"
chmod 700 "$ENV_DIR"
if [ -f /opt/isi-house/.env ] && [ ! -f "$ENV_DIR/leads.env" ]; then
  grep -E '^(TELEGRAM_BOT_TOKEN|TELEGRAM_CHAT_ID)=' /opt/isi-house/.env > "$ENV_DIR/leads.env" || true
  chmod 600 "$ENV_DIR/leads.env"
  echo "секреты Telegram перенесены"
fi
cp -a /opt/isi-house/.env "$BACKUP_DIR/old-stack.env.$(date +%F)" 2>/dev/null || true
OLD_LEADS=$(docker volume inspect isi-house_leads -f '{{.Mountpoint}}' 2>/dev/null || true)
if [ -n "$OLD_LEADS" ] && [ -f "$OLD_LEADS/leads.jsonl" ]; then
  cp -a "$OLD_LEADS/leads.jsonl" "$BACKUP_DIR/leads-old.jsonl"
  cat "$OLD_LEADS/leads.jsonl" >> "$LEADS_DIR/leads.jsonl"
  echo "старые заявки перенесены: $(wc -l < "$LEADS_DIR/leads.jsonl") шт."
fi

say "3. Исходники сайта"
if [ -n "$REPO" ]; then
  rm -rf "$SRC_DIR"
  git clone --depth 1 "$REPO" "$SRC_DIR"
else
  git -C "$SRC_DIR" pull --ff-only
fi

say "4. Публикация статики"
mkdir -p "$SITE_DIR"
rsync -a --delete "$SRC_DIR/site/" "$SITE_DIR/"
chown -R www-data:www-data "$SITE_DIR"

say "5. API заявок"
install -m 755 "$SRC_DIR/deploy/leads-api.py" "$LEADS_DIR/leads-api.py"
touch "$LEADS_DIR/leads.jsonl"
chown -R www-data:www-data "$LEADS_DIR"
install -m 644 "$SRC_DIR/deploy/isihouse-leads.service" /etc/systemd/system/isihouse-leads.service
systemctl daemon-reload
systemctl enable --now isihouse-leads
systemctl restart isihouse-leads
sleep 1
curl -fsS http://127.0.0.1:3002/api/leads/health && echo " — API отвечает"

say "6. nginx"
install -m 644 "$SRC_DIR/deploy/nginx-isihouse.conf" /etc/nginx/sites-available/isihouse
ln -sf /etc/nginx/sites-available/isihouse /etc/nginx/sites-enabled/isihouse
rm -f /etc/nginx/sites-enabled/default
nginx -t
systemctl reload nginx

say "7. Проверка"
curl -fsS -o /dev/null -w 'https://isihouse.ru → %{http_code}, %{size_download} байт\n' https://isihouse.ru/ || true
curl -fsS -o /dev/null -w 'robots.txt → %{http_code}\n' https://isihouse.ru/robots.txt || true
curl -fsS -o /dev/null -w 'llms.txt  → %{http_code}\n' https://isihouse.ru/llms.txt || true

say "Готово. Старый стек можно снять командой: bash deploy.sh --drop-old"
