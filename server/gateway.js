'use strict';

const RESOURCE_NAME = GetCurrentResourceName();
const API_VERSION = 10;
const GATEWAY_BOT_URL = `https://discord.com/api/v${API_VERSION}/gateway/bot`;

let socket = null;
let heartbeatTimer = null;
let firstHeartbeatTimer = null;
let reconnectTimer = null;
let sequence = null;
let sessionId = null;
let resumeGatewayUrl = null;
let baseGatewayUrl = null;
let heartbeatAcked = true;
let stopping = false;
let connecting = false;
let forcedResume = null;

function getRuntimeConfig() {
    const status = GetConvar('rs_discordlogs_gateway_status_runtime', 'online');
    const activityType = Number.parseInt(GetConvar('rs_discordlogs_gateway_activity_type_runtime', '3'), 10);
    const reconnectDelay = Number.parseInt(GetConvar('rs_discordlogs_gateway_reconnect_delay_runtime', '5000'), 10);

    return {
        enabled: GetConvar('rs_discordlogs_gateway_enabled_runtime', '1') === '1',
        token: GetConvar('rs_discordlogs_gateway_token_runtime', ''),
        status: ['online', 'idle', 'dnd', 'invisible'].includes(status) ? status : 'online',
        activityType: [0, 2, 3, 5].includes(activityType) ? activityType : 3,
        activityName: GetConvar('rs_discordlogs_gateway_activity_runtime', 'FiveM Logs'),
        reconnectDelay: Number.isFinite(reconnectDelay) ? Math.max(1000, reconnectDelay) : 5000,
        debug: GetConvar('rs_discordlogs_gateway_debug_runtime', '0') === '1'
    };
}

function info(message) {
    console.log(`[rs_discordlogs] [Gateway] ${message}`);
}

function debug(message) {
    if (getRuntimeConfig().debug) {
        console.log(`[rs_discordlogs] [Gateway DEBUG] ${message}`);
    }
}

function warn(message) {
    console.warn(`[rs_discordlogs] [Gateway] ${message}`);
}

function publishState(state, user = '') {
    setImmediate(() => {
        try {
            SetConvar('rs_discordlogs_gateway_state', state);
            SetConvar('rs_discordlogs_gateway_user', user || '');
        } catch (error) {
            warn(`Kon Gateway status niet publiceren: ${error.message || error}`);
        }
    });
}

function clearHeartbeat() {
    if (heartbeatTimer) {
        clearInterval(heartbeatTimer);
        heartbeatTimer = null;
    }

    if (firstHeartbeatTimer) {
        clearTimeout(firstHeartbeatTimer);
        firstHeartbeatTimer = null;
    }
}

function clearReconnect() {
    if (reconnectTimer) {
        clearTimeout(reconnectTimer);
        reconnectTimer = null;
    }
}

function gatewayUrl(url) {
    const parsed = new URL(url || 'wss://gateway.discord.gg/');
    parsed.searchParams.set('v', String(API_VERSION));
    parsed.searchParams.set('encoding', 'json');
    return parsed.toString();
}

function send(payload) {
    if (!socket || socket.readyState !== WebSocket.OPEN) {
        return false;
    }

    socket.send(JSON.stringify(payload));
    return true;
}

function heartbeat() {
    if (!socket || socket.readyState !== WebSocket.OPEN) {
        return;
    }

    if (!heartbeatAcked) {
        warn('Heartbeat ACK ontbreekt; verbinding wordt hervat.');
        requestReconnect(true);
        return;
    }

    heartbeatAcked = false;
    send({ op: 1, d: sequence });
    debug(`Heartbeat verzonden (seq=${sequence ?? 'null'}).`);
}

function startHeartbeat(interval) {
    clearHeartbeat();
    heartbeatAcked = true;

    const firstDelay = Math.floor(Math.random() * Math.max(1, interval));
    firstHeartbeatTimer = setTimeout(() => {
        heartbeat();
        heartbeatTimer = setInterval(heartbeat, interval);
    }, firstDelay);
}

function identify() {
    const config = getRuntimeConfig();
    const activities = [];

    if (config.activityName && config.activityName.trim() !== '') {
        activities.push({
            name: config.activityName.trim(),
            type: config.activityType
        });
    }

    send({
        op: 2,
        d: {
            token: config.token,
            intents: 0,
            properties: {
                os: process.platform,
                browser: 'rs_discordlogs',
                device: 'rs_discordlogs'
            },
            presence: {
                since: null,
                activities,
                status: config.status,
                afk: false
            }
        }
    });

    debug('IDENTIFY verzonden.');
}

function resume() {
    const config = getRuntimeConfig();

    if (!sessionId || sequence === null) {
        identify();
        return;
    }

    send({
        op: 6,
        d: {
            token: config.token,
            session_id: sessionId,
            seq: sequence
        }
    });

    debug(`RESUME verzonden (seq=${sequence}).`);
}

function resetSession() {
    sequence = null;
    sessionId = null;
    resumeGatewayUrl = null;
}

function scheduleConnect(canResume, delay) {
    if (stopping) {
        return;
    }

    clearReconnect();
    const config = getRuntimeConfig();
    const waitMs = Math.max(1000, delay || config.reconnectDelay);

    publishState('reconnecting');
    reconnectTimer = setTimeout(() => connect(canResume), waitMs);
}

function requestReconnect(canResume, delay) {
    if (stopping) {
        return;
    }

    forcedResume = canResume;

    if (socket && (socket.readyState === WebSocket.OPEN || socket.readyState === WebSocket.CONNECTING)) {
        try {
            socket.close(canResume ? 4000 : 1000, 'rs_discordlogs reconnect');
            return;
        } catch (error) {
            debug(`Socket sluiten mislukt: ${error.message || error}`);
        }
    }

    if (!canResume) {
        resetSession();
    }

    scheduleConnect(canResume, delay);
}

async function fetchGatewayBot() {
    const config = getRuntimeConfig();
    const response = await fetch(GATEWAY_BOT_URL, {
        method: 'GET',
        headers: {
            Authorization: `Bot ${config.token}`,
            'User-Agent': 'rs_discordlogs/1.1.0'
        }
    });

    if (!response.ok) {
        throw new Error(`Discord Gateway endpoint gaf HTTP ${response.status}`);
    }

    const data = await response.json();

    if (!data || !data.url) {
        throw new Error('Discord Gateway endpoint gaf geen URL terug.');
    }

    if (data.session_start_limit && data.session_start_limit.remaining <= 0) {
        const resetAfter = Math.max(1000, Number(data.session_start_limit.reset_after) || 60000);
        const error = new Error(`Discord IDENTIFY limiet bereikt; reset over ${resetAfter}ms.`);
        error.retryAfter = resetAfter;
        throw error;
    }

    baseGatewayUrl = data.url;
    return data.url;
}

async function connect(canResume = true) {
    if (stopping || connecting) {
        return;
    }

    const config = getRuntimeConfig();

    if (!config.enabled) {
        publishState('disabled');
        debug('Gateway is uitgeschakeld in config.');
        return;
    }

    if (!config.token) {
        publishState('missing_token');
        warn('Geen bot-token gevonden; Gateway kan niet online komen.');
        return;
    }

    connecting = true;
    clearReconnect();
    publishState('connecting');

    try {
        let url = canResume && resumeGatewayUrl ? resumeGatewayUrl : baseGatewayUrl;

        if (!url) {
            url = await fetchGatewayBot();
        }

        socket = new WebSocket(gatewayUrl(url));

        socket.onopen = () => {
            connecting = false;
            debug('WebSocket geopend; wachten op HELLO.');
        };

        socket.onmessage = (event) => {
            let payload;

            try {
                const raw = typeof event.data === 'string'
                    ? event.data
                    : Buffer.from(event.data).toString('utf8');
                payload = JSON.parse(raw);
            } catch (error) {
                warn(`Ongeldig Gateway-pakket ontvangen: ${error.message || error}`);
                return;
            }

            if (payload.s !== null && payload.s !== undefined) {
                sequence = payload.s;
            }

            switch (payload.op) {
                case 0: {
                    if (payload.t === 'READY') {
                        sessionId = payload.d.session_id;
                        resumeGatewayUrl = payload.d.resume_gateway_url;
                        const botUser = payload.d.user
                            ? `${payload.d.user.username || 'Bot'}${payload.d.user.discriminator && payload.d.user.discriminator !== '0' ? `#${payload.d.user.discriminator}` : ''}`
                            : 'Discord bot';

                        publishState('online', botUser);
                        info(`${botUser} is online en verbonden met Discord.`);
                    } else if (payload.t === 'RESUMED') {
                        publishState('online', GetConvar('rs_discordlogs_gateway_user', 'Discord bot'));
                        info('Discord Gateway sessie succesvol hervat.');
                    }
                    break;
                }

                case 1:
                    heartbeatAcked = true;
                    send({ op: 1, d: sequence });
                    heartbeatAcked = false;
                    break;

                case 7:
                    debug('Discord vroeg om reconnect/resume.');
                    requestReconnect(true, 1000);
                    break;

                case 9: {
                    const resumable = payload.d === true;
                    const randomDelay = 1000 + Math.floor(Math.random() * 4000);

                    if (!resumable) {
                        resetSession();
                    }

                    warn(`Discord meldde een ongeldige sessie (resumable=${resumable}).`);
                    requestReconnect(resumable, randomDelay);
                    break;
                }

                case 10: {
                    const interval = Number(payload.d && payload.d.heartbeat_interval);
                    if (!Number.isFinite(interval) || interval <= 0) {
                        warn('Discord HELLO bevatte geen geldige heartbeat interval.');
                        requestReconnect(false);
                        return;
                    }

                    startHeartbeat(interval);

                    if (canResume && sessionId) {
                        resume();
                    } else {
                        identify();
                    }
                    break;
                }

                case 11:
                    heartbeatAcked = true;
                    debug('Heartbeat ACK ontvangen.');
                    break;

                default:
                    break;
            }
        };

        socket.onerror = (event) => {
            const message = event && event.message ? event.message : 'onbekende WebSocket-fout';
            warn(message);
        };

        socket.onclose = (event) => {
            connecting = false;
            clearHeartbeat();

            if (stopping) {
                publishState('offline');
                return;
            }

            const code = Number(event.code || 0);
            const fatalCodes = new Set([4004, 4010, 4011, 4012, 4013, 4014]);
            const nonResumableCodes = new Set([1000, 1001, 4007, 4009]);

            if (fatalCodes.has(code)) {
                publishState('error');
                warn(`Gateway gesloten met fatale Discord-code ${code}. Controleer token/intents/config.`);
                return;
            }

            let canResumeNext;
            if (forcedResume !== null) {
                canResumeNext = forcedResume;
                forcedResume = null;
            } else {
                canResumeNext = !!sessionId && !nonResumableCodes.has(code);
            }

            if (!canResumeNext) {
                resetSession();
            }

            const delay = code === 4008 ? Math.max(10000, getRuntimeConfig().reconnectDelay) : getRuntimeConfig().reconnectDelay;
            debug(`Gateway gesloten (code=${code}); reconnect in ${delay}ms, resume=${canResumeNext}.`);
            scheduleConnect(canResumeNext, delay);
        };
    } catch (error) {
        connecting = false;
        publishState('error');

        const retryAfter = Number(error.retryAfter) || getRuntimeConfig().reconnectDelay;
        warn(`${error.message || error} Nieuwe poging volgt automatisch.`);
        scheduleConnect(false, retryAfter);
    }
}

on('rs_discordlogs:gateway:restart', () => {
    debug('Gateway restart aangevraagd.');
    forcedResume = false;
    resetSession();
    requestReconnect(false, 1000);
});

on('onResourceStop', (resourceName) => {
    if (resourceName !== RESOURCE_NAME) {
        return;
    }

    stopping = true;
    clearHeartbeat();
    clearReconnect();

    if (socket && socket.readyState === WebSocket.OPEN) {
        try {
            socket.close(1000, 'resource stop');
        } catch (_) {
            // Resource stopt toch al.
        }
    }
});

setTimeout(() => connect(false), 250);
