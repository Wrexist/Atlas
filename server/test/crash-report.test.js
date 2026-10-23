import test from 'node:test';
import assert from 'node:assert/strict';
import handler, { isValidReport, parseDsn, toSentryEvent } from '../api/crash-report.js';

function setEnv(t, vars) {
  const saved = {};
  for (const [k, v] of Object.entries(vars)) {
    saved[k] = process.env[k];
    if (v === undefined) delete process.env[k];
    else process.env[k] = v;
  }
  t.after(() => {
    for (const [k, v] of Object.entries(saved)) {
      if (v === undefined) delete process.env[k];
      else process.env[k] = v;
    }
  });
}

const DSN = 'https://abc123@o42.ingest.sentry.io/4507';

const BASE_ENV = {
  PROXY_SHARED_SECRET: 'test-secret',
  SENTRY_DSN: DSN,
  CRASH_REPORT_RPM: '1000',
  UPSTASH_REDIS_REST_URL: undefined,
  UPSTASH_REDIS_REST_TOKEN: undefined,
  KV_REST_API_URL: undefined,
  KV_REST_API_TOKEN: undefined,
};

// A per-thread MetricKit stack: the root is the innermost frame and each
// subFrame is its caller.
const CRASH_TREE = {
  callStackPerThread: true,
  callStacks: [
    {
      threadAttributed: false,
      callStackRootFrames: [{ binaryName: 'libsystem_kernel.dylib', binaryUUID: 'K-UUID', address: 0x1f00, offsetIntoBinaryTextSegment: 0xf00, sampleCount: 1 }],
    },
    {
      threadAttributed: true,
      callStackRootFrames: [{
        binaryName: 'libsystem_kernel.dylib',
        binaryUUID: 'K-UUID',
        address: 0x1abc,
        offsetIntoBinaryTextSegment: 0xabc,
        sampleCount: 1,
        subFrames: [{
          binaryName: 'Peptide',
          binaryUUID: 'APP-UUID',
          address: 0x104010,
          offsetIntoBinaryTextSegment: 0x4010,
          sampleCount: 1,
        }],
      }],
    },
  ],
};

const CRASH = {
  type: 'crash',
  metaData: {
    appVersion: '1.3.0',
    appBuildVersion: '140',
    osVersion: 'iPhone OS 18.2 (22C152)',
    deviceType: 'iPhone16,1',
    platformArchitecture: 'arm64e',
    bundleIdentifier: 'com.peptidesai.app',
    isTestFlightApp: true,
    exceptionType: 1,
    exceptionCode: 0,
    signal: 11,
    terminationReason: 'Namespace SIGNAL, Code 11',
    pid: 4242,
    regionFormat: 'SE',
  },
  callStackTree: CRASH_TREE,
};

const REPORT = { schema: 1, appBinary: 'Peptide', timeStampEnd: '2026-10-20 08:00:00 +0000', diagnostics: [CRASH] };

function stubSentry(t, { status = 200 } = {}) {
  const real = globalThis.fetch;
  const calls = [];
  globalThis.fetch = async (url, init) => {
    calls.push({ url, headers: init.headers, lines: init.body.split('\n').map((line) => JSON.parse(line)) });
    return new Response('{}', { status });
  };
  t.after(() => {
    globalThis.fetch = real;
  });
  return calls;
}

function makeReq(body, { secret = 'test-secret', contentType = 'application/json', method = 'POST' } = {}) {
  return {
    method,
    headers: { 'x-peptide-proxy': secret, 'x-real-ip': '10.2.0.1', 'content-type': contentType },
    socket: {},
    body,
  };
}

function makeRes() {
  return {
    statusCode: null,
    body: null,
    status(code) { this.statusCode = code; return this; },
    json(payload) { this.body = payload; return this; },
    send(payload) { this.body = payload; return this; },
  };
}

async function call(req) {
  const res = makeRes();
  await handler(req, res);
  return res;
}

test('test_dsn_parsesToEnvelopeUrlAndPublicKey', () => {
  assert.deepEqual(parseDsn(DSN), {
    publicKey: 'abc123',
    envelopeUrl: 'https://o42.ingest.sentry.io/api/4507/envelope/',
  });
  assert.equal(parseDsn('https://k@sentry.example.com/sub/path/9').envelopeUrl, 'https://sentry.example.com/sub/path/api/9/envelope/');
  assert.equal(parseDsn('not a dsn'), null);
  assert.equal(parseDsn('https://o42.ingest.sentry.io/4507'), null);
});

test('test_crashReport_isForwardedAsOneSentryEnvelope', async (t) => {
  setEnv(t, BASE_ENV);
  const calls = stubSentry(t);

  const res = await call(makeReq(REPORT));

  assert.equal(res.statusCode, 204);
  assert.equal(calls.length, 1);
  assert.equal(calls[0].url, 'https://o42.ingest.sentry.io/api/4507/envelope/');
  assert.equal(calls[0].headers['Content-Type'], 'application/x-sentry-envelope');
  assert.match(calls[0].headers['X-Sentry-Auth'], /sentry_version=7, sentry_key=abc123/);
  const [header, item, event] = calls[0].lines;
  assert.equal(header.event_id, event.event_id);
  assert.equal(item.type, 'event');
  assert.equal(event.level, 'fatal');
});

test('test_crashEvent_carriesReleaseStackAndImages', () => {
  const event = toSentryEvent(REPORT, CRASH);

  assert.equal(event.release, 'com.peptidesai.app@1.3.0+140');
  assert.equal(event.environment, 'testflight');
  assert.equal(event.timestamp, Date.parse('2026-10-20 08:00:00 +0000') / 1000);
  const [exception] = event.exception.values;
  assert.equal(exception.type, 'EXC_BAD_ACCESS');
  assert.equal(exception.value, 'SIGSEGV — Namespace SIGNAL, Code 11');
  assert.equal(exception.mechanism.handled, false);
  // Only the attributed thread, outermost caller first.
  assert.deepEqual(exception.stacktrace.frames.map((f) => f.instruction_addr), ['0x104010', '0x1abc']);
  assert.deepEqual(exception.stacktrace.frames.map((f) => f.in_app), [true, false]);
  assert.deepEqual(event.debug_meta.images.map((i) => [i.debug_id, i.image_addr]), [
    ['APP-UUID', '0x100000'],
    ['K-UUID', '0x1000'],
  ]);
});

test('test_crashEvent_dropsMetadataOutsideTheAllowList', () => {
  const event = toSentryEvent(REPORT, CRASH);
  assert.equal(event.extra.pid, undefined);
  assert.equal(event.extra.regionFormat, undefined);
  assert.equal(event.extra.deviceType, 'iPhone16,1');
});

test('test_objcException_namesTheEventAfterTheException', () => {
  const diagnostic = {
    ...CRASH,
    metaData: {
      ...CRASH.metaData,
      signal: 6,
      exceptionReason: {
        exceptionName: 'NSInvalidArgumentException',
        formatString: '-[%@ %@]: unrecognized selector',
        composedMessage: 'should never be forwarded',
      },
    },
  };
  const event = toSentryEvent(REPORT, diagnostic);
  assert.equal(event.exception.values[0].type, 'NSInvalidArgumentException');
  assert.equal(event.exception.values[0].value, '-[%@ %@]: unrecognized selector');
  assert.ok(!JSON.stringify(event).includes('should never be forwarded'));
});

test('test_aggregatedTree_followsTheHeaviestBranch', () => {
  const diagnostic = {
    type: 'cpu_exception',
    metaData: { totalCPUTime: '90 sec', totalSampledTime: '180 sec' },
    callStackTree: {
      callStackPerThread: false,
      callStacks: [{
        callStackRootFrames: [
          { binaryName: 'Peptide', address: 0x10, sampleCount: 2 },
          {
            binaryName: 'Peptide',
            address: 0x20,
            sampleCount: 8,
            subFrames: [
              { binaryName: 'Peptide', address: 0x30, sampleCount: 1 },
              { binaryName: 'Peptide', address: 0x40, sampleCount: 7 },
            ],
          },
        ],
      }],
    },
  };
  const event = toSentryEvent({ schema: 1, diagnostics: [diagnostic] }, diagnostic);
  assert.equal(event.level, 'warning');
  assert.equal(event.exception.values[0].value, '90 sec CPU over 180 sec');
  assert.equal(event.exception.values[0].mechanism.handled, true);
  assert.deepEqual(event.exception.values[0].stacktrace.frames.map((f) => f.instruction_addr), ['0x40', '0x20']);
});

test('test_hangWithoutCallStack_stillBuildsAnEvent', () => {
  const diagnostic = { type: 'hang', metaData: { hangDuration: '4.2 sec' } };
  const event = toSentryEvent({ schema: 1, diagnostics: [diagnostic] }, diagnostic);
  assert.equal(event.exception.values[0].type, 'App Hang');
  assert.equal(event.exception.values[0].value, 'Unresponsive for 4.2 sec');
  assert.equal(event.exception.values[0].stacktrace, undefined);
  assert.equal(event.debug_meta, undefined);
});

test('test_eachDiagnostic_becomesItsOwnEvent', async (t) => {
  setEnv(t, BASE_ENV);
  const calls = stubSentry(t);
  const hang = { type: 'hang', metaData: { hangDuration: '3 sec' } };
  const res = await call(makeReq({ ...REPORT, diagnostics: [CRASH, hang] }));
  assert.equal(res.statusCode, 204);
  assert.equal(calls.length, 2);
});

test('test_missingDsn_acceptsAndDropsTheReport', async (t) => {
  setEnv(t, { ...BASE_ENV, SENTRY_DSN: undefined });
  const calls = stubSentry(t);
  assert.equal((await call(makeReq(REPORT))).statusCode, 204);
  assert.equal(calls.length, 0);
});

test('test_unparseableDsn_acceptsAndDropsTheReport', async (t) => {
  setEnv(t, { ...BASE_ENV, SENTRY_DSN: 'nonsense' });
  const calls = stubSentry(t);
  t.mock.method(console, 'error', () => {});
  assert.equal((await call(makeReq(REPORT))).statusCode, 204);
  assert.equal(calls.length, 0);
});

test('test_wrongSecret_isRefusedBeforeContactingSentry', async (t) => {
  setEnv(t, BASE_ENV);
  const calls = stubSentry(t);
  assert.equal((await call(makeReq(REPORT, { secret: 'wrong' }))).statusCode, 401);
  assert.equal(calls.length, 0);
});

test('test_nonPost_isRefused405', async (t) => {
  setEnv(t, BASE_ENV);
  assert.equal((await call(makeReq(REPORT, { method: 'GET' }))).statusCode, 405);
});

test('test_nonJsonBody_isRefused415', async (t) => {
  setEnv(t, BASE_ENV);
  assert.equal((await call(makeReq('x', { contentType: 'text/plain' }))).statusCode, 415);
});

test('test_oversizedReport_isRefused413', async (t) => {
  setEnv(t, BASE_ENV);
  const calls = stubSentry(t);
  const huge = { ...CRASH, metaData: { ...CRASH.metaData, terminationReason: 'x'.repeat(300 * 1024) } };
  assert.equal((await call(makeReq({ ...REPORT, diagnostics: [huge] }))).statusCode, 413);
  assert.equal(calls.length, 0);
});

test('test_malformedShapes_areRefused400', async (t) => {
  setEnv(t, BASE_ENV);
  const calls = stubSentry(t);
  for (const body of [
    null,
    {},
    { ...REPORT, schema: 2 },
    { ...REPORT, diagnostics: [] },
    { ...REPORT, diagnostics: Array(11).fill(CRASH) },
    { ...REPORT, diagnostics: [{ ...CRASH, type: 'memory' }] },
    { ...REPORT, diagnostics: [{ ...CRASH, metaData: 'x' }] },
    { ...REPORT, diagnostics: [{ ...CRASH, callStackTree: [] }] },
    { ...REPORT, appBinary: 42 },
  ]) {
    assert.equal(isValidReport(body), false, JSON.stringify(body)?.slice(0, 80));
    assert.equal((await call(makeReq(body))).statusCode, 400);
  }
  assert.equal(calls.length, 0);
});

test('test_sentryFailure_answers502', async (t) => {
  setEnv(t, BASE_ENV);
  stubSentry(t, { status: 500 });
  t.mock.method(console, 'warn', () => {});
  assert.equal((await call(makeReq(REPORT))).statusCode, 502);
});

test('test_rateLimit_refusesPastThePerIpLimit', async (t) => {
  setEnv(t, { ...BASE_ENV, CRASH_REPORT_RPM: '1', SENTRY_DSN: undefined });
  const req = () => ({ ...makeReq(REPORT), headers: { ...makeReq(REPORT).headers, 'x-real-ip': 'fd00::77' } });
  assert.equal((await call(req())).statusCode, 204);
  assert.equal((await call(req())).statusCode, 429);
});
