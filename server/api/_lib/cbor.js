/**
 * Minimal CBOR codec covering exactly the subset Apple App Attest
 * blobs use: unsigned/negative integers, byte strings, text strings,
 * arrays, and maps — all definite-length. Indefinite lengths, tags,
 * and floats are rejected. Input is attacker-supplied, so lengths are
 * validated against the remaining buffer and nesting is depth-capped
 * before any allocation.
 *
 * Maps decode to `Map` (not plain objects) because COSE keys are
 * integers, including negative ones.
 */

const MAX_DEPTH = 16;

export function decodeCBOR(input) {
  const buf = Buffer.isBuffer(input) ? input : Buffer.from(input);
  const state = { buf, off: 0 };
  const value = readItem(state, 0);
  if (state.off !== buf.length) throw new Error('CBOR: trailing bytes');
  return value;
}

function need(state, n) {
  if (state.off + n > state.buf.length) throw new Error('CBOR: truncated');
}

function readLength(state, additional) {
  if (additional < 24) return additional;
  if (additional === 24) {
    need(state, 1);
    return state.buf.readUInt8(state.off++);
  }
  if (additional === 25) {
    need(state, 2);
    const v = state.buf.readUInt16BE(state.off);
    state.off += 2;
    return v;
  }
  if (additional === 26) {
    need(state, 4);
    const v = state.buf.readUInt32BE(state.off);
    state.off += 4;
    return v;
  }
  if (additional === 27) {
    need(state, 8);
    const v = state.buf.readBigUInt64BE(state.off);
    state.off += 8;
    if (v > BigInt(Number.MAX_SAFE_INTEGER)) throw new Error('CBOR: integer too large');
    return Number(v);
  }
  // 28-30 reserved, 31 indefinite — none appear in App Attest blobs.
  throw new Error('CBOR: unsupported length encoding');
}

function readItem(state, depth) {
  if (depth > MAX_DEPTH) throw new Error('CBOR: nesting too deep');
  need(state, 1);
  const initial = state.buf.readUInt8(state.off++);
  const major = initial >> 5;
  const additional = initial & 0x1f;

  switch (major) {
    case 0: // unsigned int
      return readLength(state, additional);
    case 1: // negative int
      return -1 - readLength(state, additional);
    case 2: { // byte string
      const len = readLength(state, additional);
      need(state, len);
      const bytes = state.buf.subarray(state.off, state.off + len);
      state.off += len;
      return Buffer.from(bytes);
    }
    case 3: { // text string
      const len = readLength(state, additional);
      need(state, len);
      const text = state.buf.toString('utf8', state.off, state.off + len);
      state.off += len;
      return text;
    }
    case 4: { // array
      const len = readLength(state, additional);
      const out = [];
      for (let i = 0; i < len; i += 1) out.push(readItem(state, depth + 1));
      return out;
    }
    case 5: { // map
      const len = readLength(state, additional);
      const out = new Map();
      for (let i = 0; i < len; i += 1) {
        const key = readItem(state, depth + 1);
        const value = readItem(state, depth + 1);
        out.set(key, value);
      }
      return out;
    }
    default:
      throw new Error(`CBOR: unsupported major type ${major}`);
  }
}

/**
 * Encoder for the same subset — exists so tests can assemble
 * synthetic attestation/assertion fixtures without hex literals.
 * Accepts integers, Buffers, strings, arrays, and Maps.
 */
export function encodeCBOR(value) {
  const chunks = [];
  writeItem(value, chunks);
  return Buffer.concat(chunks);
}

function writeHead(major, length, chunks) {
  if (length < 24) {
    chunks.push(Buffer.from([(major << 5) | length]));
  } else if (length < 0x100) {
    chunks.push(Buffer.from([(major << 5) | 24, length]));
  } else if (length < 0x10000) {
    const b = Buffer.alloc(3);
    b[0] = (major << 5) | 25;
    b.writeUInt16BE(length, 1);
    chunks.push(b);
  } else {
    const b = Buffer.alloc(5);
    b[0] = (major << 5) | 26;
    b.writeUInt32BE(length, 1);
    chunks.push(b);
  }
}

function writeItem(value, chunks) {
  if (typeof value === 'number') {
    if (!Number.isInteger(value)) throw new Error('CBOR encode: only integers');
    if (value >= 0) writeHead(0, value, chunks);
    else writeHead(1, -1 - value, chunks);
    return;
  }
  if (Buffer.isBuffer(value)) {
    writeHead(2, value.length, chunks);
    chunks.push(value);
    return;
  }
  if (typeof value === 'string') {
    const utf8 = Buffer.from(value, 'utf8');
    writeHead(3, utf8.length, chunks);
    chunks.push(utf8);
    return;
  }
  if (Array.isArray(value)) {
    writeHead(4, value.length, chunks);
    for (const item of value) writeItem(item, chunks);
    return;
  }
  if (value instanceof Map) {
    writeHead(5, value.size, chunks);
    for (const [k, v] of value) {
      writeItem(k, chunks);
      writeItem(v, chunks);
    }
    return;
  }
  throw new Error('CBOR encode: unsupported value type');
}
