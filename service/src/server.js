import http from 'node:http';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { DiscordService, DEFAULT_CATEGORY_CONFIG } from './discord.js';
import { GatewayPresence } from './gateway.js';
import { LicenseError, LicenseStore } from './licenses.js';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const VERSION = '3.0.0';
const HOST = process.env.HOST || '127.0.0.1';
const PORT = Math.max(1, Math.min(65535, Number(process.env.PORT) || 3099));
const BOT_TOKEN = String(process.env.DISCORD_BOT_TOKEN || '').trim();
const APPLICATION_ID = String(process.env.DISCORD_APPLICATION_ID || '').trim();
const LICENSE_FILE = process.env.LICENSE_FILE || path.resolve(__dirname, '../data/licenses.json');
const RATE_LIMIT_PER_MINUTE = Math.max(10, Number(process.env.RATE_LIMIT_PER_MINUTE) || 120);
const GATEWAY_ENABLED = String(process.env.GATEWAY_ENABLED || 'true').toLowerCase() !== 'false';
const MAX_BODY_BYTES = Math.max(16_384, Number(process.env.MAX_BODY_BYTES) || 131_072);

if (!BOT_TOKEN) {
    console.error('[rs_discordlogs-service] DISCORD_BOT_TOKEN ontbreekt.');
    process.exit(1);
}

const licenseStore = new LicenseStore(LICENSE_FILE);
const discord = new DiscordService({ token: BOT_TOKEN, applicationId: APPLICATION_ID, categoryConfig: DEFAULT_CATEGORY_CONFIG });
const rateLimits = new Map();
let gateway = null;

function sendJson(res, status, body) {
    const data = JSON.stringify(body);
    res.writeHead(status, {
        'Content-Type': 'application/json; charset=utf-8',
        'Content-Length': Buffer.byteLength(data),
        'Cache-Control': 'no-store',
        'X-Content-Type-Options': 'nosniff',
        'Referrer-Policy': 'no-referrer'
    });
    res.end(data);
}

function bearerToken(req) {
    const header = String(req.headers.authorization || '');
    const match = header.match(/^Bearer\s+(.+)$/i);
    return match ? match[1].trim() : '';
}

async function readJson(req) {
    let size = 0;
    const chunks = [];
    for await (const chunk of req) {
        size += chunk.length;
        if (size > MAX_BODY_BYTES) {
            const error = new Error('request_too_large');
            error.status = 413;
            throw error;
        }
        chunks.push(chunk);
    }
    if (!chunks.length) return {};
    try { return JSON.parse(Buffer.concat(chunks).toString('utf8')); }
    catch {
        const error = new Error('invalid_json');
        error.status = 400;
        throw error;
    }
}

function authenticate(req, data) {
    return licenseStore.authenticate({
        key: bearerToken(req),
        guildId: data.guildId,
        installId: data.installId,
        serverName: data.serverName
    });
}

function rateLimit(record) {
    const key = String(record.id || record.keyHash);
    const minute = Math.floor(Date.now() / 60_000);
    const current = rateLimits.get(key);
    if (!current || current.minute !== minute) {
        rateLimits.set(key, { minute, count: 1 });
        return true;
    }
    current.count += 1;
    return current.count <= RATE_LIMIT_PER_MINUTE;
}

async function requireBotInGuild(guildId, force = false) {
    const joined = await discord.botInGuild(guildId, force);
    return {
        joined,
        inviteUrl: discord.inviteUrl(guildId)
    };
}

function publicBot() {
    return {
        id: String(discord.botUser?.id || ''),
        username: String(discord.botUser?.username || 'Rico Scripts Logs')
    };
}

async function route(req, res) {
    const url = new URL(req.url || '/', `http://${req.headers.host || 'localhost'}`);

    if (req.method === 'GET' && url.pathname === '/health') {
        return sendJson(res, 200, { ok: true, service: 'rs_discordlogs', version: VERSION, bot: publicBot() });
    }

    if (req.method === 'GET' && url.pathname === '/v1/info') {
        const guildId = url.searchParams.get('guildId') || '';
        return sendJson(res, 200, {
            ok: true,
            version: VERSION,
            bot: publicBot(),
            applicationId: discord.applicationId,
            inviteUrl: discord.inviteUrl(guildId)
        });
    }

    if (req.method === 'POST' && url.pathname === '/v1/register') {
        const data = await readJson(req);
        const record = authenticate(req, data);
        const membership = await requireBotInGuild(data.guildId, true);
        if (!membership.joined) {
            return sendJson(res, 409, {
                ok: false,
                error: 'bot_not_in_guild',
                message: 'Nodig eerst de officiele Rico Scripts logging bot uit.',
                inviteUrl: membership.inviteUrl,
                bot: publicBot()
            });
        }

        await discord.ensureConfiguredCategories(String(data.guildId));
        return sendJson(res, 200, {
            ok: true,
            version: VERSION,
            licenseId: record.id,
            guildId: String(data.guildId),
            bot: publicBot(),
            categories: discord.configuredCategories()
        });
    }

    if (req.method === 'GET' && url.pathname === '/v1/status') {
        const data = {
            guildId: url.searchParams.get('guildId') || '',
            installId: url.searchParams.get('installId') || '',
            serverName: url.searchParams.get('serverName') || ''
        };
        const record = authenticate(req, data);
        const membership = await requireBotInGuild(data.guildId);
        return sendJson(res, 200, {
            ok: true,
            version: VERSION,
            licenseId: record.id,
            bot: publicBot(),
            botInGuild: membership.joined,
            inviteUrl: membership.joined ? null : membership.inviteUrl,
            guildId: String(data.guildId)
        });
    }

    if (req.method === 'POST' && (url.pathname === '/v1/log' || url.pathname === '/v1/test')) {
        const data = await readJson(req);
        const record = authenticate(req, data);
        if (!rateLimit(record)) {
            return sendJson(res, 429, { ok: false, error: 'rate_limited', retryAfterMs: 60_000 });
        }

        const resource = String(data.resource || 'algemeen').slice(0, 100);
        const payload = data.payload && typeof data.payload === 'object' ? data.payload : {};
        const membership = await requireBotInGuild(data.guildId);
        if (!membership.joined) {
            return sendJson(res, 409, {
                ok: false,
                error: 'bot_not_in_guild',
                inviteUrl: membership.inviteUrl,
                bot: publicBot()
            });
        }

        if (url.pathname === '/v1/test') {
            payload.type = payload.type || 'success';
            payload.title = payload.title || 'Logging kanaal bevestigd';
            payload.description = payload.description || `De officiele Rico Scripts logging bot heeft \`${resource}\` succesvol gekoppeld.`;
        }

        const target = await discord.sendLog(String(data.guildId), resource, payload);
        return sendJson(res, 200, {
            ok: true,
            route: 'official_bot',
            channel: target.channelName,
            category: target.categoryName,
            bot: publicBot()
        });
    }

    return sendJson(res, 404, { ok: false, error: 'not_found' });
}

async function main() {
    const bot = await discord.init();
    console.log(`[rs_discordlogs-service] Officiele bot: ${bot.username} (${bot.id})`);
    console.log(`[rs_discordlogs-service] License database: ${LICENSE_FILE}`);

    if (GATEWAY_ENABLED) {
        gateway = new GatewayPresence({
            token: BOT_TOKEN,
            expectedBotId: bot.id,
            status: process.env.BOT_STATUS || 'online',
            activity: process.env.BOT_ACTIVITY || 'FiveM Logs',
            activityType: Number(process.env.BOT_ACTIVITY_TYPE) || 3,
            reconnectDelay: Number(process.env.GATEWAY_RECONNECT_MS) || 5000
        });
        gateway.start().catch((error) => console.warn(`[rs_discordlogs-service] Gateway: ${error.message || error}`));
    }

    const server = http.createServer((req, res) => {
        route(req, res).catch((error) => {
            if (error instanceof LicenseError) {
                return sendJson(res, error.status, { ok: false, error: error.code, message: error.message });
            }
            const status = Number(error.status) || 500;
            if (status >= 500) console.error('[rs_discordlogs-service]', error);
            return sendJson(res, status, { ok: false, error: error.message || 'internal_error' });
        });
    });

    server.listen(PORT, HOST, () => {
        console.log(`[rs_discordlogs-service] API luistert op http://${HOST}:${PORT}`);
    });

    const shutdown = () => {
        console.log('[rs_discordlogs-service] Service stopt...');
        gateway?.stop();
        server.close(() => process.exit(0));
        setTimeout(() => process.exit(0), 5000).unref();
    };

    process.on('SIGINT', shutdown);
    process.on('SIGTERM', shutdown);
}

main().catch((error) => {
    console.error('[rs_discordlogs-service] Fatale fout:', error);
    process.exit(1);
});
