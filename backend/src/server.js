import { createServer } from 'node:http';
import { DatabaseSync } from 'node:sqlite';
import { createHash, randomBytes, randomUUID } from 'node:crypto';
import { pathToFileURL } from 'node:url';

const token = () => randomBytes(32).toString('base64url');
const hash = (s) => createHash('sha256').update(s).digest('hex');
const now = () => Date.now();
const MAX_BODY = 4096;

export function createApp({ dbPath = ':memory:', clock = now } = {}) {
  const db = new DatabaseSync(dbPath);
  db.exec(`PRAGMA journal_mode=WAL; PRAGMA foreign_keys=ON;
    CREATE TABLE IF NOT EXISTS owners (id TEXT PRIMARY KEY, token_hash TEXT UNIQUE NOT NULL);
    CREATE TABLE IF NOT EXISTS invitations (id TEXT PRIMARY KEY, owner_id TEXT NOT NULL REFERENCES owners(id), secret_hash TEXT UNIQUE NOT NULL, expires_at INTEGER NOT NULL, claimed INTEGER NOT NULL DEFAULT 0);
    CREATE TABLE IF NOT EXISTS guests (id TEXT PRIMARY KEY, owner_id TEXT NOT NULL REFERENCES owners(id), invitation_id TEXT NOT NULL UNIQUE REFERENCES invitations(id), token_hash TEXT UNIQUE NOT NULL, name TEXT NOT NULL, status TEXT NOT NULL, created_at INTEGER NOT NULL);`);
  const q = (sql, ...args) => db.prepare(sql).get(...args);
  const run = (sql, ...args) => db.prepare(sql).run(...args);
  // Conservative in-memory rate limit; deploy behind a second, shared rate limiter when scaling.
  const rates = new Map();
  const server = createServer(async (req, res) => {
    const send = (status, value) => {
      res.writeHead(status, { 'Content-Type': 'application/json; charset=utf-8', 'Cache-Control': 'no-store', 'X-Content-Type-Options': 'nosniff' });
      res.end(JSON.stringify(value));
    };
    try {
      const ip = req.socket.remoteAddress || 'unknown';
      const t = clock();
      for (const [key, entry] of rates) if (entry.until <= t) rates.delete(key);
      let entry = rates.get(ip);
      if (!entry) { entry = { count: 0, until: t + 60_000 }; rates.set(ip, entry); }
      if (++entry.count > 120) return send(429, { error: 'rate_limited' });
      const url = new URL(req.url, 'http://localhost');
      const path = url.pathname;
      if (req.method === 'GET' && path === '/health') return send(200, { ok: true });
      let body = {};
      if (req.method === 'POST') {
        let size = 0; const chunks = [];
        for await (const chunk of req) {
          size += chunk.length;
          if (size > MAX_BODY) return send(413, { error: 'body_too_large' });
          chunks.push(chunk);
        }
        try { body = JSON.parse(Buffer.concat(chunks).toString('utf8') || '{}'); } catch { return send(400, { error: 'invalid_json' }); }
        if (!body || typeof body !== 'object' || Array.isArray(body)) return send(400, { error: 'invalid_body' });
      }
      if (req.method === 'POST' && path === '/v1/owners') {
        const id = randomUUID(), secret = token();
        run('INSERT INTO owners VALUES (?, ?)', id, hash(secret));
        return send(201, { token: secret });
      }
      if (req.method === 'POST' && path === '/v1/claims') {
        if (typeof body.secret !== 'string' || !/^[A-Za-z0-9_-]{43}$/.test(body.secret) || typeof body.name !== 'string' || !body.name.trim() || body.name.trim().length > 60) return send(400, { error: 'invalid_claim' });
        const invite = q('SELECT * FROM invitations WHERE secret_hash = ?', hash(body.secret));
        if (!invite || invite.claimed || invite.expires_at <= t) return send(410, { error: 'invitation_unavailable' });
        const id = randomUUID(), guestToken = token();
        db.exec('BEGIN IMMEDIATE');
        try {
          const updated = run('UPDATE invitations SET claimed=1 WHERE id=? AND claimed=0 AND expires_at>?', invite.id, t);
          if (Number(updated.changes) !== 1) { db.exec('ROLLBACK'); return send(410, { error: 'invitation_unavailable' }); }
          run('INSERT INTO guests VALUES (?, ?, ?, ?, ?, ?, ?)', id, invite.owner_id, invite.id, hash(guestToken), body.name.trim(), 'pending', t);
          db.exec('COMMIT');
        } catch (e) { db.exec('ROLLBACK'); throw e; }
        return send(201, { token: guestToken, status: 'pending' });
      }
      const match = /^Bearer ([A-Za-z0-9_-]{43})$/.exec(req.headers.authorization || '');
      if (!match) return send(401, { error: 'unauthorized' });
      const digest = hash(match[1]);
      const owner = q('SELECT id FROM owners WHERE token_hash=?', digest);
      const guest = q('SELECT id, status FROM guests WHERE token_hash=?', digest);
      if (!owner && !guest) return send(401, { error: 'unauthorized' });
      if (guest && req.method === 'GET' && path === '/v1/guest') return send(200, { status: guest.status });
      if (!owner) return send(403, { error: 'forbidden' });
      if (req.method === 'POST' && path === '/v1/invitations') {
        const id = randomUUID(), secret = token(), expiresAt = t + 5 * 60_000;
        run('INSERT INTO invitations (id, owner_id, secret_hash, expires_at) VALUES (?, ?, ?, ?)', id, owner.id, hash(secret), expiresAt);
        return send(201, { secret, expiresAt });
      }
      if (req.method === 'GET' && path === '/v1/guests') {
        const guests = db.prepare('SELECT id, name, status, created_at AS createdAt FROM guests WHERE owner_id=? ORDER BY created_at DESC').all(owner.id);
        return send(200, { guests });
      }
      const action = /^\/v1\/guests\/([0-9a-f-]{36})\/(approve|revoke)$/.exec(path);
      if (req.method === 'POST' && action) {
        const found = q('SELECT status FROM guests WHERE id=? AND owner_id=?', action[1], owner.id);
        if (!found) return send(404, { error: 'not_found' });
        if (action[2] === 'approve' && found.status !== 'pending') return send(409, { error: 'invalid_transition' });
        const status = action[2] === 'approve' ? 'approved' : 'revoked';
        run('UPDATE guests SET status=? WHERE id=? AND owner_id=?', status, action[1], owner.id);
        return send(200, { status });
      }
      return send(404, { error: 'not_found' });
    } catch (error) {
      // Never log request bodies, bearer tokens, invitation secrets or activity.
      console.error('Request failed:', error.name);
      if (!res.headersSent) send(500, { error: 'internal_error' });
      else res.end();
    }
  });
  return { server, db };
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const { server } = createApp({ dbPath: process.env.DB_PATH || './nexalink.sqlite' });
  const port = Number(process.env.PORT || 8080);
  // Plain HTTP is intentionally loopback-only. TLS must terminate at a reverse proxy.
  server.listen(port, '127.0.0.1', () => console.log(`Pairing API listening on 127.0.0.1:${port}`));
}
