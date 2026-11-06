import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createApp } from '../src/server.js';

test('consent, isolation, revocation, single use and expiration', async (t) => {
  let time = 1000000;
  const { server, db } = createApp({ clock: () => time });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  t.after(() => { server.close(); db.close(); });
  const base = `http://127.0.0.1:${server.address().port}`;
  async function call(path, { method = 'GET', token, body } = {}) {
    const res = await fetch(base + path, { method, headers: { ...(token ? { Authorization: `Bearer ${token}` } : {}), ...(body ? { 'Content-Type': 'application/json' } : {}) }, ...(body ? { body: JSON.stringify(body) } : {}) });
    return [res.status, await res.json()];
  }
  const [, owner] = await call('/v1/owners', { method: 'POST' });
  const [, other] = await call('/v1/owners', { method: 'POST' });
  const [, invite] = await call('/v1/invitations', { method: 'POST', token: owner.token });
  assert.equal(db.prepare('SELECT secret_hash FROM invitations').get().secret_hash.includes(invite.secret), false);
  const [status, guest] = await call('/v1/claims', { method: 'POST', body: { secret: invite.secret, name: 'Téléphone invité' } });
  assert.equal(status, 201); assert.equal(guest.status, 'pending');
  assert.equal((await call('/v1/claims', { method: 'POST', body: { secret: invite.secret, name: 'Again' } }))[0], 410);
  const [, list] = await call('/v1/guests', { token: owner.token });
  const id = list.guests[0].id;
  assert.equal((await call(`/v1/guests/${id}/approve`, { method: 'POST', token: other.token }))[0], 404);
  assert.equal((await call('/v1/guests', { token: guest.token }))[0], 403);
  assert.equal((await call(`/v1/guests/${id}/approve`, { method: 'POST', token: owner.token }))[1].status, 'approved');
  assert.equal((await call('/v1/guest', { token: guest.token }))[1].status, 'approved');
  assert.equal((await call(`/v1/guests/${id}/revoke`, { method: 'POST', token: owner.token }))[1].status, 'revoked');
  assert.equal((await call(`/v1/guests/${id}/approve`, { method: 'POST', token: owner.token }))[0], 409);
  assert.equal((await call('/v1/guest', { token: guest.token }))[1].status, 'revoked');
  const [, expired] = await call('/v1/invitations', { method: 'POST', token: owner.token });
  time += 300001;
  assert.equal((await call('/v1/claims', { method: 'POST', body: { secret: expired.secret, name: 'Late' } }))[0], 410);
  assert.equal((await call('/v1/guest', { token: 'wrong' }))[0], 401);
});
