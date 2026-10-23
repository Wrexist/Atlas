/**
 * Crash and hang reports from the app's MetricKit subscriber, forwarded
 * to Sentry. The app ships no crash-reporting SDK: it posts a trimmed
 * MetricKit diagnostic payload here and this route turns each diagnostic
 * into a Sentry event.
 *
 *   POST /api/crash-report
 *   {
 *     schema: 1,
 *     appBinary?: "Peptide",                  // executable name, for in-app frames
 *     timeStampBegin?, timeStampEnd?,          // MetricKit's reporting window
 *     diagnostics: [{
 *       type: "crash" | "hang" | "cpu_exception" | "disk_write_exception" | "app_launch",
 *       metaData: { appVersion, appBuildVersion, osVersion, deviceType, ... },
 *       callStackTree?: { callStackPerThread, callStacks: [...] }
 *     }]
 *   }
 *
 * The payload carries no user identifier and no health data — only the
 * app/OS version, device model and the call stack MetricKit captured.
 *
 * Env vars:
 *   SENTRY_DSN        — the Sentry project's DSN. Unset (or unparseable):
 *                       reports are accepted and dropped with 204, so the
 *                       app can ship before the project exists.
 *   CRASH_REPORT_RPM  — per-IP requests per minute. Default 10, scaled
 *                       for shared IPv4 like every other per-IP limit.
 */
import { randomUUID } from 'node:crypto';
import { clientKey } from './_lib/anthropic-proxy.js';
import { authorize } from './_lib/auth.js';
import { allowRate, principalLimit } from './_lib/rate-limit.js';

const MAX_BODY_BYTES = 256 * 1024;
const MAX_DIAGNOSTICS = 10;
// Deep recursion stacks repeat the same frames; Sentry trims past this anyway.
const MAX_FRAMES = 200;
const MAX_STRING = 200;
const SENTRY_TIMEOUT_MS = 5000;

const TYPES = new Set(['crash', 'hang', 'cpu_exception', 'disk_write_exception', 'app_launch']);

// Scalar metadata kept on the event; anything else the client sends is ignored.
const METADATA_KEYS = [
  'appVersion', 'appBuildVersion', 'osVersion', 'deviceType', 'platformArchitecture',
  'bundleIdentifier', 'isTestFlightApp', 'lowPowerModeEnabled', 'exceptionType',
  'exceptionCode', 'signal', 'terminationReason', 'virtualMemoryRegionInfo',
  'hangDuration', 'totalCPUTime', 'totalSampledTime', 'writesCaused', 'launchDuration',
];

const SIGNALS = {
  4: 'SIGILL', 5: 'SIGTRAP', 6: 'SIGABRT', 7: 'SIGEMT', 8: 'SIGFPE',
  9: 'SIGKILL', 10: 'SIGBUS', 11: 'SIGSEGV', 12: 'SIGSYS', 13: 'SIGPIPE',
};

const MACH_EXCEPTIONS = {
  1: 'EXC_BAD_ACCESS', 2: 'EXC_BAD_INSTRUCTION', 3: 'EXC_ARITHMETIC',
  4: 'EXC_EMULATION', 5: 'EXC_SOFTWARE', 6: 'EXC_BREAKPOINT', 10: 'EXC_CRASH',
  11: 'EXC_RESOURCE', 12: 'EXC_GUARD',
};

const isObject = (value) => value !== null && typeof value === 'object' && !Array.isArray(value);
const clip = (value) => String(value).slice(0, MAX_STRING);

/** `https://<key>@<host>/<project>` → envelope URL and public key, or null. */
export function parseDsn(dsn) {
  let url;
  try {
    url = new URL(dsn);
  } catch {
    return null;
  }
  const segments = url.pathname.split('/').filter(Boolean);
  const projectId = segments.pop();
  if (!url.username || !projectId || !/^https?:$/.test(url.protocol)) return null;
  const prefix = segments.length ? `/${segments.join('/')}` : '';
  return {
    publicKey: decodeURIComponent(url.username),
    envelopeUrl: `${url.protocol}//${url.host}${prefix}/api/${projectId}/envelope/`,
  };
}

/** True when the body has the shape the app sends. */
export function isValidReport(body) {
  if (!isObject(body) || body.schema !== 1) return false;
  if (body.appBinary !== undefined && typeof body.appBinary !== 'string') return false;
  const { diagnostics } = body;
  if (!Array.isArray(diagnostics) || diagnostics.length === 0 || diagnostics.length > MAX_DIAGNOSTICS) {
    return false;
  }
  return diagnostics.every((diagnostic) => isObject(diagnostic)
    && TYPES.has(diagnostic.type)
    && (diagnostic.metaData === undefined || isObject(diagnostic.metaData))
    && (diagnostic.callStackTree === undefined || isObject(diagnostic.callStackTree)));
}

// An aggregated tree (CPU, disk writes) branches by sample count, so
// each level follows its heaviest frame; a per-thread stack has one.
function heaviest(frames) {
  if (!Array.isArray(frames)) return null;
  return frames.filter(isObject).reduce(
    (best, frame) => (!best || (frame.sampleCount ?? 0) > (best.sampleCount ?? 0) ? frame : best),
    null
  );
}

// The attributed thread's stack (the crashing thread, the hung main
// thread), else the first.
function stackFrames(tree) {
  const stacks = Array.isArray(tree?.callStacks) ? tree.callStacks.filter(isObject) : [];
  const stack = stacks.find((candidate) => candidate.threadAttributed === true) ?? stacks[0];
  const chain = [];
  for (let frame = heaviest(stack?.callStackRootFrames); frame && chain.length < MAX_FRAMES; frame = heaviest(frame.subFrames)) {
    chain.push(frame);
  }
  return chain;
}

const hex = (value) => `0x${value.toString(16)}`;

// MetricKit lists the innermost frame first; Sentry wants it last.
function sentryStack(tree, appBinary) {
  const chain = stackFrames(tree).filter((frame) => Number.isSafeInteger(frame.address));
  const images = new Map();
  const frames = chain.reverse().map((frame) => {
    const name = typeof frame.binaryName === 'string' ? clip(frame.binaryName) : undefined;
    const offset = Number.isSafeInteger(frame.offsetIntoBinaryTextSegment) ? frame.offsetIntoBinaryTextSegment : null;
    const imageAddr = offset !== null && frame.address >= offset ? hex(frame.address - offset) : undefined;
    if (imageAddr && typeof frame.binaryUUID === 'string' && !images.has(frame.binaryUUID)) {
      images.set(frame.binaryUUID, {
        type: 'macho',
        debug_id: clip(frame.binaryUUID),
        code_file: name,
        image_addr: imageAddr,
      });
    }
    return {
      instruction_addr: hex(frame.address),
      image_addr: imageAddr,
      package: name,
      in_app: Boolean(appBinary) && name === appBinary,
    };
  });
  return { frames, images: [...images.values()] };
}

function metadataOf(diagnostic) {
  const source = diagnostic.metaData ?? {};
  const kept = {};
  for (const key of METADATA_KEYS) {
    const value = source[key];
    if (['string', 'number', 'boolean'].includes(typeof value)) {
      kept[key] = typeof value === 'string' ? clip(value) : value;
    }
  }
  const reason = source.exceptionReason;
  if (isObject(reason)) {
    for (const key of ['exceptionName', 'className', 'formatString']) {
      if (typeof reason[key] === 'string') kept[`objc_${key}`] = clip(reason[key]);
    }
  }
  return kept;
}

function exceptionOf(type, meta) {
  switch (type) {
    case 'crash': {
      const signal = SIGNALS[meta.signal] ?? (meta.signal !== undefined ? `signal ${meta.signal}` : null);
      const mach = MACH_EXCEPTIONS[meta.exceptionType];
      const detail = [signal, meta.terminationReason].filter(Boolean).join(' — ');
      if (meta.objc_exceptionName) {
        return { type: meta.objc_exceptionName, value: meta.objc_formatString || detail || 'Uncaught exception' };
      }
      return { type: mach ?? signal ?? 'Crash', value: detail || 'App crashed' };
    }
    case 'hang':
      return { type: 'App Hang', value: `Unresponsive for ${meta.hangDuration ?? 'an unknown time'}` };
    case 'cpu_exception':
      return { type: 'CPU Exception', value: `${meta.totalCPUTime ?? '?'} CPU over ${meta.totalSampledTime ?? '?'}` };
    case 'disk_write_exception':
      return { type: 'Disk Write Exception', value: `${meta.writesCaused ?? 'Excessive'} written` };
    default:
      return { type: 'Slow App Launch', value: `Launch took ${meta.launchDuration ?? 'too long'}` };
  }
}

const LEVELS = { crash: 'fatal', hang: 'error', app_launch: 'warning' };

function timestampOf(report) {
  const parsed = Date.parse(report.timeStampEnd ?? '');
  return (Number.isFinite(parsed) ? parsed : Date.now()) / 1000;
}

/** One Sentry event for one MetricKit diagnostic. */
export function toSentryEvent(report, diagnostic) {
  const meta = metadataOf(diagnostic);
  const { frames, images } = sentryStack(diagnostic.callStackTree, report.appBinary);
  const exception = exceptionOf(diagnostic.type, meta);
  const release = meta.bundleIdentifier && meta.appVersion
    ? `${meta.bundleIdentifier}@${meta.appVersion}${meta.appBuildVersion ? `+${meta.appBuildVersion}` : ''}`
    : undefined;
  return {
    event_id: randomUUID().replaceAll('-', ''),
    timestamp: timestampOf(report),
    platform: 'cocoa',
    level: LEVELS[diagnostic.type] ?? 'warning',
    logger: 'metrickit',
    release,
    dist: meta.appBuildVersion,
    environment: meta.isTestFlightApp ? 'testflight' : 'production',
    tags: {
      diagnostic_type: diagnostic.type,
      device_model: meta.deviceType,
      os_version: meta.osVersion,
    },
    contexts: {
      os: { name: 'iOS', version: meta.osVersion },
      device: { model: meta.deviceType, arch: meta.platformArchitecture },
      app: { app_version: meta.appVersion, app_build: meta.appBuildVersion },
    },
    exception: {
      values: [{
        ...exception,
        mechanism: { type: 'metrickit', handled: diagnostic.type !== 'crash' },
        stacktrace: frames.length ? { frames } : undefined,
      }],
    },
    debug_meta: images.length ? { images } : undefined,
    extra: meta,
  };
}

async function sendToSentry(sentry, event) {
  const envelope = [
    JSON.stringify({ event_id: event.event_id, sent_at: new Date().toISOString() }),
    JSON.stringify({ type: 'event' }),
    JSON.stringify(event),
  ].join('\n');
  const response = await fetch(sentry.envelopeUrl, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/x-sentry-envelope',
      'X-Sentry-Auth': `Sentry sentry_version=7, sentry_key=${sentry.publicKey}, sentry_client=atlas-proxy/1.0`,
    },
    body: envelope,
    signal: AbortSignal.timeout(SENTRY_TIMEOUT_MS),
  });
  if (!response.ok) throw new Error(`Sentry answered ${response.status}`);
}

function bodyTooLarge(req) {
  const contentLength = parseInt(req.headers['content-length'] || '0', 10);
  if (contentLength > MAX_BODY_BYTES) return true;
  // Chunked uploads carry no content-length, so measure the parsed body too.
  return Buffer.byteLength(JSON.stringify(req.body ?? ''), 'utf8') > MAX_BODY_BYTES;
}

export default async function handler(req, res) {
  if (req.method !== 'POST') {
    res.status(405).json({ error: { message: 'Use POST' } });
    return;
  }
  if (!authorize(req)) {
    res.status(401).json({ error: { message: 'Unauthorised' } });
    return;
  }
  const ip = clientKey(req);
  const limit = parseInt(process.env.CRASH_REPORT_RPM || '10', 10);
  if (!(await allowRate({ name: 'crash-report', key: ip, limit: principalLimit(`ip:${ip}`, limit), windowSeconds: 60 }))) {
    res.status(429).json({ error: { message: 'Too many requests' } });
    return;
  }
  if (!/^application\/json\b/i.test(req.headers['content-type'] || '')) {
    res.status(415).json({ error: { message: 'Unsupported content type' } });
    return;
  }
  if (bodyTooLarge(req)) {
    res.status(413).json({ error: { message: 'Report too large' } });
    return;
  }
  if (!isValidReport(req.body)) {
    res.status(400).json({ error: { message: 'Malformed request body' } });
    return;
  }

  const sentry = process.env.SENTRY_DSN ? parseDsn(process.env.SENTRY_DSN) : null;
  if (!sentry) {
    if (process.env.SENTRY_DSN) console.error('[crash-report] SENTRY_DSN is not a valid DSN; report dropped');
    res.status(204).send('');
    return;
  }

  const results = await Promise.allSettled(
    req.body.diagnostics.map((diagnostic) => sendToSentry(sentry, toSentryEvent(req.body, diagnostic)))
  );
  const failed = results.filter((result) => result.status === 'rejected');
  if (failed.length) {
    console.warn(`[crash-report] ${failed.length}/${results.length} events not delivered: ${failed[0].reason?.message}`);
    res.status(502).json({ error: { message: 'Report not delivered' } });
    return;
  }
  res.status(204).send('');
}
