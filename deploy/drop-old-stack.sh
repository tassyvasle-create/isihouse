#!/usr/bin/env bash
# Снятие старой версии сайта (Next 14 + Docker Compose) после успешного запуска v2.
# Секреты и заявки сохраняются в /opt/backups. Запускать от root ПОСЛЕ проверки нового сайта.
set -euo pipefail
BACKUP_DIR=/opt/backups
mkdir -p "$BACKUP_DIR"

echo "==> Бэкап секретов и данных старого стека"
cp -a /opt/isi-house/.env "$BACKUP_DIR/old-stack.env.$(date +%F)" 2>/dev/null || true
OLD_LEADS=$(docker volume inspect isi-house_leads -f '{{.Mountpoint}}' 2>/dev/null || true)
[ -n "$OLD_LEADS" ] && [ -f "$OLD_LEADS/leads.jsonl" ] && cp -a "$OLD_LEADS/leads.jsonl" "$BACKUP_DIR/leads-old.jsonl" || true
if docker ps -a --format '{{.Names}}' | grep -q postgres; then
  docker exec "$(docker ps --format '{{.Names}}' | grep postgres | head -1)" \
    pg_dump -U isi isihouse > "$BACKUP_DIR/isihouse-db-$(date +%F).sql" 2>/dev/null || true
fi

echo "==> Останавливаем контейнеры"
cd /opt/isi-house 2>/dev/null && docker compose down --volumes --remove-orphans || true

echo "==> Удаляем каталог проекта и образы"
rm -rf /opt/isi-house
docker image prune -af || true
docker volume prune -f || true

echo "==> Осталось на диске:"
df -h / | tail -1
echo "Бэкапы: $(ls -1 $BACKUP_DIR 2>/dev/null | tr '\n' ' ')"
