/* ============================================================
   NovaPOS — website + MongoDB Atlas sync bridge (ek hi server)
   ------------------------------------------------------------
   Chalane ka tareeqa (isi folder mein):
     npm install
     node server.js
   Phir browser mein:  http://localhost:4500
   Database "novapos" aur collection "appdata" khud ban jayengi.

   Hosting (live link): repo ko Render.com / Railway pe connect
   karein — start command `node server.js`. Wahan ye server site
   bhi serve karta hai aur /api/data se Atlas sync bhi, is liye
   live link pe sync automatic kaam karti hai (same origin).
   ============================================================ */
const http = require('http');
const fs = require('fs');
const path = require('path');
const { MongoClient } = require('mongodb');

/* ---- aap ka Atlas cluster (password included) ---- */
const MONGO_URI = 'mongodb+srv://saadahmedfurrukh9_db_user:saad123@cluster0.ykybqcm.mongodb.net/novapos?retryWrites=true&w=majority';
const DB_NAME = 'novapos';
const PORT = process.env.PORT || 4500;

/* ---- static website files ---- */
const STATIC = {
  '/': 'index.html',
  '/index.html': 'index.html',
  '/style.css': 'style.css',
  '/app.js': 'app.js'
};
const MIME = { '.html': 'text/html; charset=utf-8', '.css': 'text/css; charset=utf-8', '.js': 'text/javascript; charset=utf-8' };

let coll = null;
MongoClient.connect(MONGO_URI)
  .then(client => {
    coll = client.db(DB_NAME).collection('appdata');
    console.log('MongoDB Atlas connected ✓');
  })
  .catch(e => console.error('MongoDB connect failed:', e.message));

const send = (res, code, obj) => {
  res.writeHead(code, {
    'Content-Type': 'application/json',
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers': 'Content-Type',
    'Access-Control-Allow-Methods': 'GET,POST,OPTIONS'
  });
  res.end(JSON.stringify(obj));
};

http.createServer((req, res) => {
  const url = (req.url || '/').split('?')[0];

  if (req.method === 'OPTIONS') return send(res, 204, {});

  /* ---------- API ---------- */
  if (url.startsWith('/api/data') && req.method === 'GET') {
    if (!coll) return send(res, 503, { ok: false, error: 'MongoDB not connected yet' });
    coll.findOne({ _id: 'snapshot' })
      .then(doc => send(res, 200, { ok: true, snapshot: doc }))
      .catch(e => send(res, 500, { ok: false, error: e.message }));
    return;
  }
  if (url.startsWith('/api/data') && req.method === 'POST') {
    let body = '';
    req.on('data', c => { body += c; if (body.length > 20e6) req.destroy(); });
    req.on('end', () => {
      if (!coll) return send(res, 503, { ok: false, error: 'MongoDB not connected yet' });
      try {
        const payload = JSON.parse(body);
        coll.replaceOne(
          { _id: 'snapshot' },
          { _id: 'snapshot', savedAt: Number(payload.savedAt) || Date.now(), data: payload.data },
          { upsert: true }
        ).then(() => send(res, 200, { ok: true }))
          .catch(e => send(res, 500, { ok: false, error: e.message }));
      } catch (e) {
        send(res, 400, { ok: false, error: e.message });
      }
    });
    return;
  }

  /* ---------- static site ---------- */
  const file = STATIC[url];
  if (file && (req.method === 'GET' || req.method === 'HEAD')) {
    const full = path.join(__dirname, file);
    fs.readFile(full, (err, buf) => {
      if (err) { res.writeHead(404); return res.end('not found'); }
      res.writeHead(200, { 'Content-Type': MIME[path.extname(file)] || 'application/octet-stream', 'Cache-Control': 'no-cache' });
      res.end(buf);
    });
    return;
  }

  res.writeHead(404, { 'Content-Type': 'text/plain' });
  res.end('not found');
}).listen(PORT, () => console.log(`NovaPOS running → http://localhost:${PORT}`));
