#!/usr/bin/env node
import fs from 'node:fs';
import fsp from 'node:fs/promises';
import path from 'node:path';
import os from 'node:os';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const STORE_PATH = process.env.OPENCLAW_CODEX_AUTH_STORE || '/Users/xbr/.openclaw/agents/main/agent/auth-profiles.json';
const PROFILE_ID = process.env.OPENCLAW_CODEX_PROFILE_ID || 'openai-codex:default';
const THRESHOLD_MS = Number(process.env.OPENCLAW_CODEX_REFRESH_THRESHOLD_MS || 24 * 60 * 60 * 1000);
const RETRY_AFTER_FAILURE_MS = Number(process.env.OPENCLAW_CODEX_REFRESH_RETRY_AFTER_FAILURE_MS || 60 * 60 * 1000);
const ALERT_AFTER_FAILURES = Number(process.env.OPENCLAW_CODEX_REFRESH_ALERT_AFTER_FAILURES || 3);
const LOCK_DIR = path.join(os.homedir(), '.openclaw', 'workspace', 'locks');
const LOCK_PATH = path.join(LOCK_DIR, 'codex-oauth-refresh-watchdog.lock');
const LOCK_STALE_MS = Number(process.env.OPENCLAW_CODEX_REFRESH_LOCK_STALE_MS || 20 * 60 * 1000);
const LOG_PATH = process.env.OPENCLAW_CODEX_REFRESH_LOG || '/Users/xbr/.openclaw/workspace/logs/codex-oauth-refresh-watchdog.log';
const STATE_PATH = process.env.OPENCLAW_CODEX_REFRESH_STATE || '/Users/xbr/.openclaw/workspace/state/codex-oauth-refresh-watchdog.json';
const CONFIG_PATH = process.env.OPENCLAW_CONFIG || '/Users/xbr/.openclaw/openclaw.json';
const RUNTIME_MODULE = process.env.OPENCLAW_CODEX_RUNTIME_MODULE || '/opt/homebrew/lib/node_modules/openclaw/dist/extensions/openai/openai-codex-provider.runtime.js';

function nowIso() { return new Date().toISOString(); }
function log(line) {
  fs.mkdirSync(path.dirname(LOG_PATH), { recursive: true });
  fs.appendFileSync(LOG_PATH, `${nowIso()} ${line}\n`, { mode: 0o600 });
}
function readStore() {
  return JSON.parse(fs.readFileSync(STORE_PATH, 'utf8'));
}
function readJsonFile(filePath, fallback) {
  try {
    return JSON.parse(fs.readFileSync(filePath, 'utf8'));
  } catch (err) {
    if (err?.code === 'ENOENT') return fallback;
    throw err;
  }
}
function saveJsonAtomic(filePath, value) {
  const dir = path.dirname(filePath);
  fs.mkdirSync(dir, { recursive: true });
  const tmp = path.join(dir, `.${path.basename(filePath)}.${process.pid}.tmp`);
  fs.writeFileSync(tmp, JSON.stringify(value, null, 2) + '\n', { mode: 0o600 });
  fs.renameSync(tmp, filePath);
}
function saveStoreAtomic(store) {
  const dir = path.dirname(STORE_PATH);
  const base = path.basename(STORE_PATH);
  const tmp = path.join(dir, `.${base}.${process.pid}.tmp`);
  const backup = path.join(dir, `${base}.bak-${new Date().toISOString().replace(/[:.]/g, '-')}`);
  const current = fs.readFileSync(STORE_PATH);
  fs.writeFileSync(backup, current, { mode: 0o600 });
  fs.writeFileSync(tmp, JSON.stringify(store, null, 2) + '\n', { mode: 0o600 });
  fs.renameSync(tmp, STORE_PATH);
}
function publicState(cred) {
  const remainingMs = Number(cred?.expires) - Date.now();
  return {
    profile: PROFILE_ID,
    provider: cred?.provider,
    type: cred?.type,
    email: cred?.email,
    expires: Number.isFinite(Number(cred?.expires)) ? new Date(Number(cred.expires)).toISOString() : null,
    remainingMinutes: Number.isFinite(remainingMs) ? Math.round(remainingMs / 60000) : null,
  };
}

function publicError(err) {
  return String(err?.message || err || 'unknown error')
    .replace(/(access[_-]?token|refresh[_-]?token|id[_-]?token|token)[^,\s]*/gi, '$1=<redacted>')
    .slice(0, 600);
}

function resolveTelegramTarget(config) {
  const explicitChat = process.env.OPENCLAW_CODEX_REFRESH_ALERT_CHAT_ID;
  const botToken = process.env.OPENCLAW_CODEX_REFRESH_TELEGRAM_BOT_TOKEN
    || config?.channels?.telegram?.botToken;
  const chatId = explicitChat
    || config?.channels?.telegram?.execApprovals?.approvers?.[0]
    || config?.tools?.elevated?.allowFrom?.telegram?.[0]
    || config?.channels?.telegram?.groupAllowFrom?.[0];
  return { botToken, chatId };
}

function curlQuote(value) {
  return String(value).replace(/\\/g, '\\\\').replace(/"/g, '\\"').replace(/\n/g, '\\n');
}

function sendTelegramAlert(message) {
  const config = readJsonFile(CONFIG_PATH, {});
  const { botToken, chatId } = resolveTelegramTarget(config);
  if (!botToken || !chatId) {
    log('alert skipped: telegram bot token or chat id not configured');
    return false;
  }
  const payload = {
    chat_id: chatId,
    text: message,
    disable_web_page_preview: true,
  };
  const curlConfig = [
    `url = "${curlQuote(`https://api.telegram.org/bot${botToken}/sendMessage`)}"`,
    'request = "POST"',
    'header = "Content-Type: application/json"',
    `data = "${curlQuote(JSON.stringify(payload))}"`,
    'max-time = 20',
    'silent',
    'show-error',
    'fail',
    '',
  ].join('\n');
  const result = spawnSync('/usr/bin/curl', ['--config', '-'], {
    input: curlConfig,
    encoding: 'utf8',
    env: process.env,
  });
  if (result.status === 0) return true;
  log(`alert send failed status=${result.status ?? 'null'} stderr=${String(result.stderr || '').slice(0, 300)}`);
  return false;
}

function loadState() {
  const state = readJsonFile(STATE_PATH, {});
  const profileState = state[PROFILE_ID] || {};
  return { state, profileState };
}

function saveProfileState(state, profileState) {
  state[PROFILE_ID] = profileState;
  saveJsonAtomic(STATE_PATH, state);
}

function resetFailureState() {
  const { state } = loadState();
  saveProfileState(state, {
    failureCount: 0,
    lastFailureAt: null,
    lastSuccessAt: nowIso(),
    lastAlertAt: null,
    alertSentForFailureCount: 0,
  });
}

function recordFailure(err, cred) {
  const { state, profileState } = loadState();
  const failureCount = Number(profileState.failureCount || 0) + 1;
  const nextState = {
    ...profileState,
    failureCount,
    lastFailureAt: nowIso(),
    lastFailureMessage: publicError(err),
    lastSuccessAt: profileState.lastSuccessAt || null,
  };
  const alreadyAlerted = Number(profileState.alertSentForFailureCount || 0) >= ALERT_AFTER_FAILURES;
  if (failureCount >= ALERT_AFTER_FAILURES && !alreadyAlerted) {
    const expires = publicState(cred).expires;
    const message = [
      'OpenClaw OAuth refresh failed.',
      `Provider: openai-codex`,
      `Profile: ${PROFILE_ID}`,
      `Failures: ${failureCount}`,
      `Token expires: ${expires}`,
      `Last error: ${nextState.lastFailureMessage}`,
      '',
      'Action required: re-auth with openclaw models auth login --provider openai-codex if refresh keeps failing.',
    ].join('\n');
    if (sendTelegramAlert(message)) {
      nextState.lastAlertAt = nowIso();
      nextState.alertSentForFailureCount = failureCount;
      log(`alert sent failureCount=${failureCount} profile=${PROFILE_ID}`);
    }
  }
  saveProfileState(state, nextState);
}

async function acquireLock() {
  await fsp.mkdir(LOCK_DIR, { recursive: true });
  const payload = JSON.stringify({ pid: process.pid, startedAt: new Date().toISOString() });
  try {
    const handle = await fsp.open(LOCK_PATH, 'wx');
    await handle.writeFile(payload);
    await handle.close();
    return true;
  } catch (err) {
    if (err?.code !== 'EEXIST') throw err;
    try {
      const stat = await fsp.stat(LOCK_PATH);
      if (Date.now() - stat.mtimeMs > LOCK_STALE_MS) {
        await fsp.rm(LOCK_PATH, { force: true });
        const handle = await fsp.open(LOCK_PATH, 'wx');
        await handle.writeFile(payload);
        await handle.close();
        log('stale_lock_replaced', { lock: LOCK_PATH });
        return true;
      }
    } catch (inner) {
      if (inner?.code === 'ENOENT') return acquireLock();
      throw inner;
    }
    log('skip locked', { lock: LOCK_PATH });
    return false;
  }
}

async function releaseLock() {
  await fsp.rm(LOCK_PATH, { force: true }).catch(() => {});
}

async function main() {
  const lockAcquired = await acquireLock();
  if (!lockAcquired) return;
  try {
  const store = readStore();
  const cred = store?.profiles?.[PROFILE_ID];
  if (!cred || cred.type !== 'oauth' || cred.provider !== 'openai-codex') {
    throw new Error(`OAuth profile not found or incompatible: ${PROFILE_ID}`);
  }
  if (!cred.refresh) throw new Error(`OAuth profile has no refresh token: ${PROFILE_ID}`);

  const remainingMs = Number(cred.expires) - Date.now();
  if (Number.isFinite(remainingMs) && remainingMs > THRESHOLD_MS) {
    log(`skip fresh ${JSON.stringify(publicState(cred))}`);
    console.log(`fresh: expires=${publicState(cred).expires}, remainingMinutes=${publicState(cred).remainingMinutes}`);
    return;
  }

  const { profileState } = loadState();
  const lastFailureMs = Date.parse(profileState.lastFailureAt || '');
  const retryWaitMs = Number.isFinite(lastFailureMs) ? RETRY_AFTER_FAILURE_MS - (Date.now() - lastFailureMs) : 0;
  if (Number(profileState.failureCount || 0) > 0 && retryWaitMs > 0) {
    log(`skip retry_wait ${JSON.stringify({ profile: PROFILE_ID, failureCount: profileState.failureCount, retryInMinutes: Math.ceil(retryWaitMs / 60000) })}`);
    return;
  }

  try {
    log(`refresh_start ${JSON.stringify(publicState(cred))}`);
    const { refreshOpenAICodexToken } = await import(fileURLToPath(new URL(`file://${RUNTIME_MODULE}`)));
    const refreshed = await refreshOpenAICodexToken(cred.refresh);
    if (!refreshed?.access || !refreshed?.refresh || !refreshed?.expires) {
      throw new Error('Refresh returned incomplete credentials');
    }

    const next = {
      ...store,
      profiles: {
        ...store.profiles,
        [PROFILE_ID]: {
          ...cred,
          ...refreshed,
          type: 'oauth',
          provider: 'openai-codex',
          email: cred.email,
        },
      },
    };
    saveStoreAtomic(next);
    resetFailureState();
    const after = next.profiles[PROFILE_ID];
    log(`refresh_ok ${JSON.stringify(publicState(after))}`);
    console.log(`refreshed: expires=${publicState(after).expires}, remainingMinutes=${publicState(after).remainingMinutes}`);
  } catch (err) {
    recordFailure(err, cred);
    throw err;
  }
  } finally {
    await releaseLock();
  }
}

main().catch((err) => {
  log(`refresh_error ${err?.stack || err}`);
  console.error(err?.message || String(err));
  process.exit(1);
});
