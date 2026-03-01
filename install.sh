#!/bin/bash
set -e

echo "==> Creating project structure..."
mkdir -p wl-checker/backend wl-checker/frontend

# ── backend/app.py ──────────────────────────────────────────
cat > wl-checker/backend/app.py << 'PYEOF'
from flask import Flask, request, jsonify, send_from_directory
from flask_cors import CORS
import requests
import ipaddress
import sqlite3
import datetime
import os

app = Flask(__name__, static_folder='../frontend', static_url_path='')
CORS(app)

DB_PATH = '/data/history.db'

def get_db():
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    return conn

def init_db():
    os.makedirs('/data', exist_ok=True)
    with get_db() as db:
        db.execute('''
            CREATE TABLE IF NOT EXISTS history (
                id          INTEGER PRIMARY KEY AUTOINCREMENT,
                query       TEXT NOT NULL,
                ip          TEXT,
                asn         TEXT,
                country     TEXT,
                whitelisted INTEGER,
                checked_at  TEXT
            )
        ''')
        db.commit()

API_URL = 'http://api.uzuk.pro/check'

def check_one(query):
    r = requests.get(API_URL, params={'query': query}, timeout=10)
    r.raise_for_status()
    return r.json()

def expand_cidr(cidr, limit=64):
    net = ipaddress.ip_network(cidr, strict=False)
    hosts = list(net.hosts()) or [net.network_address]
    return [str(h) for h in hosts[:limit]]

def expand_range(start, end, limit=64):
    s = ipaddress.ip_address(start)
    e = ipaddress.ip_address(end)
    ips, cur = [], s
    while cur <= e and len(ips) < limit:
        ips.append(str(cur))
        cur += 1
    return ips

def save_result(data):
    with get_db() as db:
        db.execute(
            'INSERT INTO history (query,ip,asn,country,whitelisted,checked_at) VALUES (?,?,?,?,?,?)',
            (data.get('query'), data.get('ip'), data.get('asn'),
             data.get('country'), 1 if data.get('whitelisted') else 0,
             datetime.datetime.utcnow().isoformat())
        )
        db.commit()

@app.route('/')
def index():
    return send_from_directory('../frontend', 'index.html')

@app.route('/api/check')
def api_check():
    q = request.args.get('query', '').strip()
    if not q:
        return jsonify({'error': 'query is required'}), 400
    results, errors = [], []
    try:
        if '/' in q:
            for ip in expand_cidr(q):
                try:
                    d = check_one(ip); save_result(d); results.append(d)
                except Exception as e:
                    errors.append({'query': ip, 'error': str(e)})
        elif '-' in q and not q.startswith('-'):
            parts = q.split('-', 1)
            try:
                for ip in expand_range(parts[0].strip(), parts[1].strip()):
                    try:
                        d = check_one(ip); save_result(d); results.append(d)
                    except Exception as e:
                        errors.append({'query': ip, 'error': str(e)})
            except ValueError:
                d = check_one(q); save_result(d); results.append(d)
        else:
            d = check_one(q); save_result(d); results.append(d)
    except Exception as e:
        return jsonify({'error': str(e)}), 502
    return jsonify({'results': results, 'errors': errors})

@app.route('/api/history')
def api_history():
    limit = min(int(request.args.get('limit', 50)), 200)
    with get_db() as db:
        rows = db.execute('SELECT * FROM history ORDER BY id DESC LIMIT ?', (limit,)).fetchall()
    return jsonify([dict(r) for r in rows])

@app.route('/api/history/clear', methods=['DELETE'])
def api_history_clear():
    with get_db() as db:
        db.execute('DELETE FROM history')
        db.commit()
    return jsonify({'ok': True})

if __name__ == '__main__':
    init_db()
    app.run(host='0.0.0.0', port=5000)
PYEOF

# ── backend/requirements.txt ────────────────────────────────
cat > wl-checker/backend/requirements.txt << 'EOF'
flask==3.1.0
flask-cors==5.0.1
requests==2.32.3
gunicorn==23.0.0
EOF

# ── backend/__init__.py ─────────────────────────────────────
touch wl-checker/backend/__init__.py

# ── frontend/index.html ─────────────────────────────────────
cat > wl-checker/frontend/index.html << 'EOF'
<!DOCTYPE html>
<html lang="ru">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <title>WL Checker</title>
  <link href="https://fonts.googleapis.com/css2?family=JetBrains+Mono:ital,wght@0,300;0,400;0,600;1,300&display=swap" rel="stylesheet" />
  <style>
    *, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }
    :root {
      --bg: #080808; --surface: #0f0f0f; --surface2: #141414;
      --border: #1c1c1c; --border2: #252525;
      --text: #e2e2e2; --muted: #3a3a3a; --muted2: #5a5a5a; --muted3: #888;
      --green: #22c55e; --green-bg: rgba(34,197,94,0.07); --green-border: rgba(34,197,94,0.2);
      --red: #ef4444; --red-bg: rgba(239,68,68,0.07); --red-border: rgba(239,68,68,0.2);
      --mono: 'JetBrains Mono', monospace;
    }
    html, body { height: 100%; background: var(--bg); color: var(--text); font-family: var(--mono); font-size: 13px; }
    body { display: flex; flex-direction: column; align-items: center; min-height: 100vh; padding: 52px 20px 40px; }
    .wrap { width: 100%; max-width: 620px; }
    header { text-align: center; margin-bottom: 40px; animation: fadeUp .4s ease both; }
    .eyebrow { font-size: 10px; letter-spacing: .35em; text-transform: uppercase; color: var(--muted2); margin-bottom: 10px; }
    h1 { font-size: 26px; font-weight: 600; letter-spacing: -.02em; }
    h1 em { font-style: normal; color: var(--muted2); font-weight: 300; }
    .tagline { font-size: 11px; color: var(--muted2); margin-top: 6px; letter-spacing: .05em; }
    .tabs { display: flex; border-bottom: 1px solid var(--border); margin-bottom: 24px; animation: fadeUp .4s .05s ease both; }
    .tab { background: none; border: none; color: var(--muted2); font-family: var(--mono); font-size: 11px; letter-spacing: .1em; text-transform: uppercase; padding: 10px 18px; cursor: pointer; border-bottom: 2px solid transparent; margin-bottom: -1px; transition: color .2s, border-color .2s; }
    .tab:hover { color: var(--text); }
    .tab.active { color: var(--text); border-bottom-color: var(--text); }
    .panel { display: none; } .panel.active { display: block; }
    .input-group { animation: fadeUp .4s .1s ease both; }
    .input-row { display: flex; background: var(--surface); border: 1px solid var(--border); border-radius: 5px; overflow: hidden; transition: border-color .2s; }
    .input-row:focus-within { border-color: var(--border2); }
    .prompt { padding: 0 14px; display: flex; align-items: center; color: var(--muted2); border-right: 1px solid var(--border); font-size: 12px; user-select: none; }
    input[type=text] { flex: 1; background: transparent; border: none; outline: none; color: var(--text); font-family: var(--mono); font-size: 13px; padding: 13px 16px; }
    input::placeholder { color: var(--muted); }
    .check-btn { background: transparent; border: none; border-left: 1px solid var(--border); color: var(--muted2); font-family: var(--mono); font-size: 10px; letter-spacing: .15em; text-transform: uppercase; padding: 0 20px; cursor: pointer; transition: color .2s, background .2s; white-space: nowrap; }
    .check-btn:hover { color: var(--text); background: var(--surface2); }
    .check-btn:disabled { opacity: .4; cursor: default; }
    .hint { font-size: 10px; color: var(--muted2); margin-top: 7px; padding-left: 2px; letter-spacing: .02em; }
    .loader { font-size: 10px; letter-spacing: .2em; color: var(--muted2); text-transform: uppercase; text-align: center; padding: 20px; animation: blink 1s ease-in-out infinite; display: none; }
    .loader.show { display: block; }
    #results { display: flex; flex-direction: column; gap: 7px; margin-top: 20px; }
    .card { background: var(--surface); border: 1px solid var(--border); border-radius: 5px; padding: 13px 16px; display: grid; grid-template-columns: 1fr auto; gap: 5px 10px; animation: slideIn .2s ease both; }
    .card.ok  { border-left: 2px solid var(--green); background: linear-gradient(90deg, var(--green-bg) 0%, transparent 55%); }
    .card.bad { border-left: 2px solid var(--red);   background: linear-gradient(90deg, var(--red-bg)   0%, transparent 55%); }
    .card-query { font-size: 13px; font-weight: 600; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
    .badge { font-size: 9px; letter-spacing: .12em; text-transform: uppercase; padding: 3px 8px; border-radius: 3px; align-self: center; white-space: nowrap; }
    .ok .badge { background: var(--green-bg); color: var(--green); border: 1px solid var(--green-border); }
    .bad .badge { background: var(--red-bg); color: var(--red); border: 1px solid var(--red-border); }
    .card-meta { font-size: 11px; color: var(--muted3); grid-column: 1/-1; }
    .card-meta b { color: var(--muted2); font-weight: 400; margin-right: 3px; }
    .err-card { background: var(--red-bg); border: 1px solid var(--red-border); color: var(--red); border-radius: 5px; padding: 11px 14px; font-size: 11px; animation: slideIn .2s ease both; }
    .history-header { display: flex; justify-content: space-between; align-items: center; margin-bottom: 14px; }
    .history-header span { font-size: 10px; letter-spacing: .1em; text-transform: uppercase; color: var(--muted2); }
    .clear-btn { background: none; border: 1px solid var(--border); color: var(--muted2); font-family: var(--mono); font-size: 10px; letter-spacing: .1em; text-transform: uppercase; padding: 5px 12px; border-radius: 4px; cursor: pointer; transition: color .2s, border-color .2s; }
    .clear-btn:hover { color: var(--red); border-color: var(--red-border); }
    #history-list { display: flex; flex-direction: column; gap: 6px; }
    .h-row { background: var(--surface); border: 1px solid var(--border); border-radius: 4px; padding: 10px 14px; display: grid; grid-template-columns: auto 1fr auto; gap: 4px 12px; align-items: center; font-size: 11px; }
    .h-dot { width: 6px; height: 6px; border-radius: 50%; flex-shrink: 0; }
    .h-dot.ok { background: var(--green); } .h-dot.bad { background: var(--red); }
    .h-query { font-weight: 600; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
    .h-time { color: var(--muted2); font-size: 10px; white-space: nowrap; }
    .h-meta { grid-column: 2/-1; color: var(--muted3); font-size: 10px; }
    .empty { text-align: center; padding: 40px; font-size: 11px; color: var(--muted2); letter-spacing: .05em; }
    footer { margin-top: auto; padding-top: 48px; font-size: 10px; color: var(--muted); letter-spacing: .05em; text-align: center; }
    @keyframes fadeUp  { from { opacity:0; transform:translateY(10px) } to { opacity:1; transform:none } }
    @keyframes slideIn { from { opacity:0; transform:translateY(5px)  } to { opacity:1; transform:none } }
    @keyframes blink   { 0%,100% { opacity:.3 } 50% { opacity:1 } }
  </style>
</head>
<body>
<div class="wrap">
  <header>
    <div class="eyebrow">uzuk.pro · api</div>
    <h1>WL <em>/</em> Checker</h1>
    <p class="tagline">проверка IP · домена · диапазона</p>
  </header>
  <div class="tabs">
    <button class="tab active" onclick="switchTab('check',this)">Проверка</button>
    <button class="tab" onclick="switchTab('history',this)">История</button>
  </div>
  <div class="panel active" id="tab-check">
    <div class="input-group">
      <div class="input-row">
        <div class="prompt">$</div>
        <input id="queryInput" type="text" placeholder="8.8.8.8 / ya.ru / 192.168.1.0/24" autocomplete="off" spellcheck="false" />
        <button class="check-btn" id="checkBtn" onclick="runCheck()">Check</button>
      </div>
      <p class="hint">поддерживается: одиночный IP, домен, CIDR, диапазон IP-IP (до 64 хостов)</p>
    </div>
    <div class="loader" id="loader">checking...</div>
    <div id="results"></div>
  </div>
  <div class="panel" id="tab-history">
    <div class="history-header">
      <span>последние запросы</span>
      <button class="clear-btn" onclick="clearHistory()">Очистить</button>
    </div>
    <div id="history-list"><div class="empty">история пуста</div></div>
  </div>
</div>
<footer>powered by api.uzuk.pro</footer>
<script>
  const $ = id => document.getElementById(id);
  function switchTab(name, el) {
    document.querySelectorAll('.tab').forEach(t => t.classList.remove('active'));
    document.querySelectorAll('.panel').forEach(p => p.classList.remove('active'));
    el.classList.add('active'); $('tab-'+name).classList.add('active');
    if (name === 'history') loadHistory();
  }
  async function runCheck() {
    const q = $('queryInput').value.trim(); if (!q) return;
    $('results').innerHTML = ''; $('loader').classList.add('show'); $('checkBtn').disabled = true;
    try {
      const r = await fetch('/api/check?query='+encodeURIComponent(q));
      const data = await r.json();
      if (data.error) { renderError(data.error); return; }
      (data.results||[]).forEach(renderCard);
      (data.errors||[]).forEach(e => renderError(e.query+': '+e.error));
      if (!data.results?.length && !data.errors?.length) renderError('Нет результатов');
    } catch(e) { renderError(e.message); }
    finally { $('loader').classList.remove('show'); $('checkBtn').disabled = false; }
  }
  function renderCard(d) {
    const ok = d.whitelisted, el = document.createElement('div');
    el.className = 'card '+(ok?'ok':'bad');
    el.innerHTML = '<div class="card-query">'+esc(d.query)+'</div>'
      +'<div class="badge">'+(ok?'Whitelist ✓':'Not listed')+'</div>'
      +'<div class="card-meta"><b>ip</b>'+esc(d.ip||'—')+'&nbsp;&nbsp;<b>asn</b>'+esc(d.asn||'—')+'&nbsp;&nbsp;<b>cc</b>'+esc(d.country||'—')+'</div>';
    $('results').appendChild(el);
  }
  function renderError(msg) {
    const el = document.createElement('div'); el.className = 'err-card';
    el.textContent = 'Ошибка: '+msg; $('results').appendChild(el);
  }
  async function loadHistory() {
    try {
      const rows = await (await fetch('/api/history?limit=100')).json();
      const list = $('history-list');
      if (!rows.length) { list.innerHTML = '<div class="empty">история пуста</div>'; return; }
      list.innerHTML = rows.map(row => {
        const ok = row.whitelisted, time = (row.checked_at||'').replace('T',' ').slice(0,19);
        return '<div class="h-row"><div class="h-dot '+(ok?'ok':'bad')+'"></div>'
          +'<div class="h-query">'+esc(row.query)+'</div><div class="h-time">'+time+'</div>'
          +'<div class="h-meta"><b>ip</b> '+esc(row.ip||'—')+' &nbsp;<b>asn</b> '+esc(row.asn||'—')+' &nbsp;<b>cc</b> '+esc(row.country||'—')+'</div></div>';
      }).join('');
    } catch(e) { $('history-list').innerHTML = '<div class="empty">ошибка: '+e.message+'</div>'; }
  }
  async function clearHistory() {
    if (!confirm('Очистить всю историю?')) return;
    await fetch('/api/history/clear', {method:'DELETE'}); loadHistory();
  }
  function esc(s) { return String(s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;'); }
  $('queryInput').addEventListener('keydown', e => { if (e.key==='Enter') runCheck(); });
</script>
</body>
</html>
EOF

# ── Dockerfile ──────────────────────────────────────────────
cat > wl-checker/Dockerfile << 'EOF'
FROM python:3.12-slim
WORKDIR /app
COPY backend/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY backend/ ./backend/
COPY frontend/ ./frontend/
RUN mkdir -p /data
ENV PYTHONUNBUFFERED=1
EXPOSE 5000
CMD ["gunicorn", "--bind", "0.0.0.0:5000", "--workers", "2", "--timeout", "60", "backend.app:app"]
EOF

# ── docker-compose.yml ──────────────────────────────────────
cat > wl-checker/docker-compose.yml << 'EOF'
version: '3.9'
services:
  wl-checker:
    build: .
    container_name: wl-checker
    restart: unless-stopped
    ports:
      - "5000:5000"
    volumes:
      - wl-data:/data
volumes:
  wl-data:
EOF

echo "==> Building and starting Docker..."
cd wl-checker
docker compose up -d --build

echo ""
echo "✅ Done! Site is running at http://$(hostname -I | awk '{print $1}'):5000"
