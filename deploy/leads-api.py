#!/usr/bin/env python3
"""isi.house — минимальный API заявок (stdlib only).
POST /api/leads  {name, phone, projectType?, message?, preferredTime?, source, role?, consent:true}
Пишет в JSONL и шлёт уведомление в Telegram. Секреты — из /etc/isihouse/leads.env.
"""
import json, os, re, time, urllib.request, urllib.parse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

ENV = {}
try:
    with open('/etc/isihouse/leads.env') as f:
        for line in f:
            line = line.strip()
            if line and not line.startswith('#') and '=' in line:
                k, v = line.split('=', 1)
                ENV[k.strip()] = v.strip().strip('"').strip("'")
except FileNotFoundError:
    pass

TG_TOKEN = ENV.get('TELEGRAM_BOT_TOKEN', '')
TG_CHAT = ENV.get('TELEGRAM_CHAT_ID', '')
DATA = '/opt/isi-leads/leads.jsonl'
os.makedirs(os.path.dirname(DATA), exist_ok=True)

RATE = {}  # ip -> [timestamps]
TYPES = {'kitchen':'Кухня','wardrobe':'Гардеробная','closet':'Шкаф / встройка','panels':'Стеновые панели','full':'Комплектация под ключ','other':'Другое'}
TIMES = {'any':'В любое время','morning':'Утром','day':'Днём','evening':'Вечером'}
ROLES = {'designer':'Дизайнер интерьера','developer':'Застройщик','contractor':'Ремонтная бригада','other':'Другое'}

def tg_send(text):
    if not TG_TOKEN or not TG_CHAT:
        return
    try:
        req = urllib.request.Request(
            f'https://api.telegram.org/bot{TG_TOKEN}/sendMessage',
            data=urllib.parse.urlencode({'chat_id': TG_CHAT, 'text': text}).encode(),
            method='POST')
        urllib.request.urlopen(req, timeout=10)
    except Exception:
        pass

class H(BaseHTTPRequestHandler):
    server_version = 'isihouse-leads'
    def log_message(self, *a):  # тихие логи
        pass

    def _json(self, code, obj):
        body = json.dumps(obj, ensure_ascii=False).encode()
        self.send_response(code)
        self.send_header('Content-Type', 'application/json; charset=utf-8')
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_POST(self):
        if self.path != '/api/leads':
            return self._json(404, {'ok': False})
        ip = self.headers.get('X-Real-IP') or self.client_address[0]
        now = time.time()
        RATE[ip] = [t for t in RATE.get(ip, []) if now - t < 600]
        if len(RATE[ip]) >= 5:
            return self._json(429, {'ok': False, 'error': 'Слишком часто. Позвоните нам: 8-909-463-22-23'})
        try:
            raw = self.rfile.read(min(int(self.headers.get('Content-Length', 0)), 65536))
            d = json.loads(raw)
        except Exception:
            return self._json(400, {'ok': False, 'error': 'bad json'})
        if d.get('company_site'):  # honeypot
            return self._json(200, {'ok': True})
        name = str(d.get('name', '')).strip()[:80]
        phone = re.sub(r'\D', '', str(d.get('phone', '')))
        consent = d.get('consent') is True
        if len(name) < 2 or len(phone) != 11 or not consent:
            return self._json(400, {'ok': False, 'error': 'Не удалось отправить заявку. Позвоните нам: 8-909-463-22-23'})
        source = str(d.get('source', 'form'))[:20]
        lead = {
            'name': name, 'phone': '+' + phone,
            'projectType': str(d.get('projectType', ''))[:20],
            'message': str(d.get('message', ''))[:1000],
            'preferredTime': str(d.get('preferredTime', ''))[:20],
            'role': str(d.get('role', ''))[:20],
            'source': source,
            'consent': {'given': True, 'docVersion': '1.0 от 19.08.2026', 'at': time.strftime('%Y-%m-%dT%H:%M:%S%z')},
            'ip': ip,
            'createdAt': time.strftime('%Y-%m-%dT%H:%M:%S%z'),
        }
        RATE[ip].append(now)
        with open(DATA, 'a') as f:
            f.write(json.dumps(lead, ensure_ascii=False) + '\n')
        msk = time.strftime('%d.%m.%Y %H:%M', time.localtime())
        if source == 'partner':
            text = (f'Новый партнёр с сайта\nИмя: {name}\nТелефон: +{phone}\n'
                    f'Профиль: {ROLES.get(lead["role"], lead["role"] or "—")}\nВремя: {msk} (сервер)')
        else:
            text = ('Новая заявка с сайта\nИмя: ' + name + '\nТелефон: +' + phone +
                    '\nТип: ' + TYPES.get(lead['projectType'], lead['projectType'] or '—') +
                    '\nУдобное время: ' + TIMES.get(lead['preferredTime'], lead['preferredTime'] or '—') +
                    '\nСообщение: ' + (lead['message'] or '—') +
                    '\nИсточник: ' + source + '\nВремя: ' + msk + ' (сервер)')
        tg_send(text)
        return self._json(200, {'ok': True, 'id': str(int(now * 1000))})

    def do_GET(self):
        if self.path == '/api/leads/health':
            return self._json(200, {'ok': True})
        return self._json(404, {'ok': False})

if __name__ == '__main__':
    ThreadingHTTPServer(('127.0.0.1', 3002), H).serve_forever()
