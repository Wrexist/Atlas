import test from 'node:test';
import assert from 'node:assert/strict';
import { decodeCBOR, encodeCBOR } from '../api/_lib/cbor.js';

const hex = (s) => Buffer.from(s.replace(/\s/g, ''), 'hex');

test('decodes RFC 8949 integer vectors', () => {
  assert.equal(decodeCBOR(hex('00')), 0);
  assert.equal(decodeCBOR(hex('17')), 23);
  assert.equal(decodeCBOR(hex('1818')), 24);
  assert.equal(decodeCBOR(hex('190100')), 256);
  assert.equal(decodeCBOR(hex('1a000f4240')), 1_000_000);
  assert.equal(decodeCBOR(hex('20')), -1);
  assert.equal(decodeCBOR(hex('3863')), -100);
});

test('decodes byte strings, text, arrays, maps', () => {
  assert.deepEqual(decodeCBOR(hex('4401020304')), Buffer.from([1, 2, 3, 4]));
  assert.equal(decodeCBOR(hex('63666f6f')), 'foo');
  assert.deepEqual(decodeCBOR(hex('83010203')), [1, 2, 3]);
  const map = decodeCBOR(hex('a201020304'));
  assert.ok(map instanceof Map);
  assert.equal(map.get(1), 2);
  assert.equal(map.get(3), 4);
});

test('decodes COSE-style maps with negative integer keys', () => {
  // {1: 2, -1: 1, -2: h'aabb'} — the shape of an EC2 COSE key.
  const map = decodeCBOR(hex('a3 0102 2001 21 42aabb'));
  assert.equal(map.get(1), 2);
  assert.equal(map.get(-1), 1);
  assert.deepEqual(map.get(-2), Buffer.from([0xaa, 0xbb]));
});

test('rejects indefinite lengths, floats, truncation, trailing bytes', () => {
  assert.throws(() => decodeCBOR(hex('5f')), /unsupported length/);
  assert.throws(() => decodeCBOR(hex('fa47c35000')), /unsupported major/);
  assert.throws(() => decodeCBOR(hex('4401')), /truncated/);
  assert.throws(() => decodeCBOR(hex('0000')), /trailing/);
});

test('rejects pathological nesting', () => {
  // 20 nested single-element arrays around int 0.
  const deep = Buffer.concat([Buffer.alloc(20, 0x81), Buffer.from([0x00])]);
  assert.throws(() => decodeCBOR(deep), /nesting too deep/);
});

test('round-trips the attestation object shape', () => {
  const attestation = new Map([
    ['fmt', 'apple-appattest'],
    ['attStmt', new Map([
      ['x5c', [Buffer.from('leaf-der'), Buffer.from('intermediate-der')]],
      ['receipt', Buffer.from('receipt-bytes')],
    ])],
    ['authData', Buffer.alloc(87, 7)],
  ]);
  const decoded = decodeCBOR(encodeCBOR(attestation));
  assert.equal(decoded.get('fmt'), 'apple-appattest');
  assert.deepEqual(decoded.get('attStmt').get('x5c')[1], Buffer.from('intermediate-der'));
  assert.equal(decoded.get('authData').length, 87);
});

test('round-trips two-byte and four-byte lengths', () => {
  const big = Buffer.alloc(70_000, 0xab);
  assert.deepEqual(decodeCBOR(encodeCBOR(big)), big);
  const mid = 'x'.repeat(300);
  assert.equal(decodeCBOR(encodeCBOR(mid)), mid);
});
