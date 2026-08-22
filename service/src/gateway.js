const GATEWAY_BOT_URL = 'https://discord.com/api/v10/gateway/bot';

function sleep(ms) {
    return new Promise((resolve) => setTimeout(resolve, ms));
}

export class GatewayPresence {
    constructor({ token, expectedBotId, status = 'online', activity = 'FiveM Logs', activityType = 3, reconnectDelay = 5000 }) {
        this.token = token;
        this.expectedBotId = String(expectedBotId || '');
        this.status = ['online', 'idle', 'dnd', 'invisible'].includes(status) ? status : 'online';
        this.activity = String(activity || 'FiveM Logs');
        this.activityType = [0, 2, 3, 5].includes(Number(activityType)) ? Number(activityType) : 3;
        this.reconnectDelay = Math.max(1000, Number(reconnectDelay) || 5000);
        this.socket = null;
        this.sequence = null;
        this.sessionId = null;
        this.resumeUrl = null;
        this.heartbeatTimer = null;
        this.reconnectTimer = null;
        this.stopping = false;
        this.heartbeatAcked = true;
    }

    async gatewayUrl() {
        const response = await fetch(GATEWAY_BOT_URL, {
            headers: { Authorization: `Bot ${this.token}`, 'User-Agent': 'Rico-Scripts-rs_discordlogs/3.0.0' }
        });
        if (!response.ok) throw new Error(`Gateway endpoint HTTP ${response.status}`);
        const data = await response.json();
        if (!data?.url) throw new Error('Gateway endpoint gaf geen URL terug.');
        return data.url;
    }

    wsUrl(base) {
        const url = new URL(base || 'wss://gateway.discord.gg/');
        url.searchParams.set('v', '10');
        url.searchParams.set('encoding', 'json');
        return url.toString();
    }

    clearHeartbeat() {
        if (this.heartbeatTimer) clearInterval(this.heartbeatTimer);
        this.heartbeatTimer = null;
    }

    send(payload) {
        if (!this.socket || this.socket.readyState !== WebSocket.OPEN) return false;
        this.socket.send(JSON.stringify(payload));
        return true;
    }

    heartbeat() {
        if (!this.heartbeatAcked) {
            try { this.socket?.close(4000, 'heartbeat timeout'); } catch {}
            return;
        }
        this.heartbeatAcked = false;
        this.send({ op: 1, d: this.sequence });
    }

    identify() {
        this.send({
            op: 2,
            d: {
                token: this.token,
                intents: 0,
                properties: { os: process.platform, browser: 'rs_discordlogs', device: 'rs_discordlogs' },
                presence: {
                    since: null,
                    activities: this.activity ? [{ name: this.activity, type: this.activityType }] : [],
                    status: this.status,
                    afk: false
                }
            }
        });
    }

    resume() {
        if (!this.sessionId || this.sequence === null) return this.identify();
        this.send({ op: 6, d: { token: this.token, session_id: this.sessionId, seq: this.sequence } });
    }

    scheduleReconnect() {
        if (this.stopping) return;
        clearTimeout(this.reconnectTimer);
        this.reconnectTimer = setTimeout(() => this.connect(true).catch((error) => {
            console.warn(`[rs_discordlogs-service] Gateway reconnect: ${error.message || error}`);
            this.scheduleReconnect();
        }), this.reconnectDelay);
    }

    async connect(canResume = true) {
        if (this.stopping) return;
        if (typeof WebSocket === 'undefined') throw new Error('Node runtime heeft geen WebSocket support; gebruik Node.js 22+.');

        const base = canResume && this.resumeUrl ? this.resumeUrl : await this.gatewayUrl();
        const socket = new WebSocket(this.wsUrl(base));
        this.socket = socket;

        socket.onmessage = (event) => {
            let payload;
            try { payload = JSON.parse(typeof event.data === 'string' ? event.data : Buffer.from(event.data).toString('utf8')); }
            catch { return; }

            if (payload.s !== null && payload.s !== undefined) this.sequence = payload.s;

            if (payload.op === 10) {
                const interval = Number(payload.d?.heartbeat_interval);
                if (!Number.isFinite(interval) || interval <= 0) return socket.close(4000, 'bad hello');
                this.clearHeartbeat();
                this.heartbeatAcked = true;
                setTimeout(() => this.heartbeat(), Math.floor(Math.random() * interval));
                this.heartbeatTimer = setInterval(() => this.heartbeat(), interval);
                if (canResume && this.sessionId) this.resume(); else this.identify();
            } else if (payload.op === 11) {
                this.heartbeatAcked = true;
            } else if (payload.op === 7) {
                socket.close(4000, 'discord reconnect');
            } else if (payload.op === 9) {
                if (payload.d !== true) {
                    this.sessionId = null;
                    this.sequence = null;
                    this.resumeUrl = null;
                }
                setTimeout(() => socket.close(4000, 'invalid session'), 1000 + Math.floor(Math.random() * 4000));
            } else if (payload.op === 0 && payload.t === 'READY') {
                const userId = String(payload.d?.user?.id || '');
                if (!userId || userId !== this.expectedBotId) {
                    console.error(`[rs_discordlogs-service] Gateway bot-ID mismatch: expected ${this.expectedBotId}, got ${userId || 'none'}`);
                    this.stopping = true;
                    return socket.close(4004, 'wrong bot');
                }
                this.sessionId = payload.d.session_id;
                this.resumeUrl = payload.d.resume_gateway_url;
                console.log(`[rs_discordlogs-service] Officiele bot ${payload.d.user.username} is online.`);
            } else if (payload.op === 0 && payload.t === 'RESUMED') {
                console.log('[rs_discordlogs-service] Gateway sessie hervat.');
            } else if (payload.op === 1) {
                this.send({ op: 1, d: this.sequence });
            }
        };

        socket.onclose = () => {
            this.clearHeartbeat();
            if (!this.stopping) this.scheduleReconnect();
        };

        socket.onerror = () => {};
    }

    async start() {
        while (!this.stopping) {
            try {
                await this.connect(false);
                return;
            } catch (error) {
                console.warn(`[rs_discordlogs-service] Gateway start mislukt: ${error.message || error}`);
                await sleep(this.reconnectDelay);
            }
        }
    }

    stop() {
        this.stopping = true;
        clearTimeout(this.reconnectTimer);
        this.clearHeartbeat();
        try { this.socket?.close(1000, 'service stop'); } catch {}
    }
}
