import test from 'node:test';
import assert from 'node:assert/strict';
import { authorize } from '../api/_lib/auth.js';
import { setEnv } from '../testutil/attest-fixtures.js';

const req = (secret) => ({ headers: secret === undefined ? {} : { 'x-peptide-proxy': secret } });

test('accepts the current secret, rejects wrong or missing ones', (t) => {
  setEnv(t, { PROXY_SHARED_SECRET: 'current', PROXY_SHARED_SECRET_NEXT: undefined });
  assert.equal(authorize(req('current')), true);
  assert.equal(authorize(req('wrong')), false);
  assert.equal(authorize(req('')), false);
  assert.equal(authorize(req(undefined)), false);
});

test('accepts the staged next secret during rotation', (t) => {
  setEnv(t, { PROXY_SHARED_SECRET: 'current', PROXY_SHARED_SECRET_NEXT: 'next' });
  assert.equal(authorize(req('current')), true);
  assert.equal(authorize(req('next')), true);
  assert.equal(authorize(req('wrong')), false);
});

test('fails closed when no secret is configured', (t) => {
  setEnv(t, { PROXY_SHARED_SECRET: undefined, PROXY_SHARED_SECRET_NEXT: 'next' });
  // _NEXT alone must not authorize — the primary slot is the gate.
  assert.equal(authorize(req('next')), false);
});
