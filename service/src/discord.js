const API_BASE = 'https://discord.com/api/v10';
const BOT_PERMISSIONS = '85008';

const COLORS = {
    info: 3447003,
    success: 5763719,
    warning: 16776960,
    error: 15548997,
    security: 15158332,
    admin: 10181046,
    money: 15844367
};

const DEFAULT_CATEGORY_CONFIG = {
    defaultCategory: 'Onbekende Scripts',
    generalCategory: 'Algemene Logs',
    autoMoveExisting: true,
    generalResources: [
        'connections',
        'algemeen',
        'resources',
        'server',
        'rs_discordlogs'
    ]
};

function sleep(ms) {
    return new Promise((resolve) => setTimeout(resolve, ms));
}

function truncate(value, max) {
    const text = String(value ?? '');
    if (text.length <= max) return text;
    if (max <= 3) return text.slice(0, max);
    return `${text.slice(0, max - 3)}...`;
}

function sanitizeChannelName(value) {
    let text = String(value || '').toLowerCase();
    text = text.replace(/_/g, '-').replace(/\s+/g, '-').replace(/[^a-z0-9-]/g, '-');
    text = text.replace(/-+/g, '-').replace(/^-+|-+$/g, '');
    if (!text) text = 'algemene-logs';
    return text.slice(0, 90).replace(/-+$/g, '') || 'algemene-logs';
}

function sanitizeCategoryName(value, fallback = 'Onbekende Scripts') {
    let text = String(value || '')
        .replace(/[\r\n\t\0]/g, ' ')
        .replace(/\s+/g, ' ')
        .trim();

    // Voorkom dat een author-veld eruitziet als een Discord mention.
    text = text.replace(/@everyone/gi, 'everyone').replace(/@here/gi, 'here');
    if (!text) text = fallback;
    return truncate(text, 100) || fallback;
}

function validImageUrl(value) {
    if (!value) return null;
    try {
        const url = new URL(String(value));
        if (url.protocol !== 'http:' && url.protocol !== 'https:') return null;
        return url.toString();
    } catch {
        return null;
    }
}

function normalizeFields(fields, max = 25) {
    if (!Array.isArray(fields)) return [];
    return fields.slice(0, Math.min(25, max)).filter((field) => field && typeof field === 'object').map((field) => ({
        name: truncate(field.name || 'Info', 256),
        value: truncate(field.value || '-', 1024) || '-',
        inline: field.inline === true
    }));
}

export class DiscordService {
    constructor({ token, applicationId = '', categoryConfig = null }) {
        this.token = String(token || '').trim();
        this.applicationId = String(applicationId || '').trim();
        this.botUser = null;
        this.categoryConfig = categoryConfig || DEFAULT_CATEGORY_CONFIG;
        this.guildCaches = new Map();
        this.membershipCache = new Map();
    }

    async request(method, path, body = null, attempt = 1) {
        const response = await fetch(`${API_BASE}${path}`, {
            method,
            headers: {
                Authorization: `Bot ${this.token}`,
                'Content-Type': 'application/json',
                'User-Agent': 'Rico-Scripts-rs_discordlogs/3.1.0'
            },
            body: body === null ? undefined : JSON.stringify(body)
        });

        let data = null;
        const text = await response.text();
        if (text) {
            try { data = JSON.parse(text); } catch { data = null; }
        }

        if (response.status === 429 && attempt < 5) {
            const seconds = Number(data?.retry_after) || 1;
            await sleep(Math.max(250, Math.floor(seconds * 1000)));
            return this.request(method, path, body, attempt + 1);
        }

        if (response.status >= 500 && attempt < 3) {
            await sleep(750 * attempt);
            return this.request(method, path, body, attempt + 1);
        }

        if (!response.ok) {
            const error = new Error(`Discord HTTP ${response.status}`);
            error.status = response.status;
            error.data = data;
            throw error;
        }

        return data;
    }

    async init() {
        if (!this.token) throw new Error('DISCORD_BOT_TOKEN ontbreekt.');
        const user = await this.request('GET', '/users/@me');
        if (!user?.id || user.bot !== true) throw new Error('DISCORD_BOT_TOKEN hoort niet bij een bot-account.');
        this.botUser = user;
        if (!this.applicationId) this.applicationId = String(user.id);
        return user;
    }

    inviteUrl(guildId = '') {
        const params = new URLSearchParams({
            client_id: this.applicationId,
            permissions: BOT_PERMISSIONS,
            scope: 'bot'
        });
        if (guildId) {
            params.set('guild_id', String(guildId));
            params.set('disable_guild_select', 'true');
        }
        return `https://discord.com/oauth2/authorize?${params.toString()}`;
    }

    isGeneralResource(resourceName) {
        const name = String(resourceName || '').toLowerCase();
        return (this.categoryConfig.generalResources || []).some((entry) => String(entry || '').toLowerCase() === name);
    }

    categoryForResource(resourceName, maker = '') {
        if (this.isGeneralResource(resourceName)) {
            return sanitizeCategoryName(this.categoryConfig.generalCategory, 'Algemene Logs');
        }

        const normalizedMaker = sanitizeCategoryName(maker, '');
        if (normalizedMaker) return normalizedMaker;

        return sanitizeCategoryName(this.categoryConfig.defaultCategory, 'Onbekende Scripts');
    }

    configuredCategories() {
        const set = new Set([
            sanitizeCategoryName(this.categoryConfig.generalCategory, 'Algemene Logs'),
            sanitizeCategoryName(this.categoryConfig.defaultCategory, 'Onbekende Scripts')
        ]);
        return [...set].filter(Boolean).sort((a, b) => a.localeCompare(b));
    }

    async botInGuild(guildId, force = false) {
        const key = String(guildId);
        const cached = this.membershipCache.get(key);
        if (!force && cached && cached.expiresAt > Date.now()) return cached.value;

        let value = false;
        try {
            await this.request('GET', `/guilds/${encodeURIComponent(key)}`);
            value = true;
        } catch (error) {
            if (error.status !== 403 && error.status !== 404) throw error;
        }

        this.membershipCache.set(key, { value, expiresAt: Date.now() + 60_000 });
        return value;
    }

    async refreshGuild(guildId) {
        const channels = await this.request('GET', `/guilds/${encodeURIComponent(guildId)}/channels`);
        const cache = { categories: new Map(), text: [] };

        for (const channel of Array.isArray(channels) ? channels : []) {
            if (channel.type === 4 && channel.id && channel.name) {
                cache.categories.set(String(channel.name).toLowerCase(), String(channel.id));
            } else if (channel.type === 0 && channel.id && channel.name) {
                cache.text.push({
                    id: String(channel.id),
                    name: String(channel.name),
                    parentId: channel.parent_id ? String(channel.parent_id) : null
                });
            }
        }

        this.guildCaches.set(String(guildId), cache);
        return cache;
    }

    async guildCache(guildId) {
        return this.guildCaches.get(String(guildId)) || this.refreshGuild(guildId);
    }

    async ensureCategory(guildId, categoryName) {
        const cache = await this.guildCache(guildId);
        const safeName = sanitizeCategoryName(categoryName, 'Onbekende Scripts');
        const key = safeName.toLowerCase();
        const existing = cache.categories.get(key);
        if (existing) return existing;

        const created = await this.request('POST', `/guilds/${encodeURIComponent(guildId)}/channels`, {
            name: safeName,
            type: 4
        });

        if (!created?.id) throw new Error(`Discord categorie ${safeName} kon niet worden aangemaakt.`);
        cache.categories.set(key, String(created.id));
        return String(created.id);
    }

    async ensureConfiguredCategories(guildId) {
        for (const category of this.configuredCategories()) {
            await this.ensureCategory(guildId, category);
        }
    }

    async ensureChannel(guildId, resourceName, maker = '') {
        const channelName = sanitizeChannelName(resourceName);
        const categoryName = this.categoryForResource(resourceName, maker);
        const parentId = await this.ensureCategory(guildId, categoryName);
        const cache = await this.guildCache(guildId);

        const exact = cache.text.find((channel) => channel.name.toLowerCase() === channelName && channel.parentId === parentId);
        if (exact) return { id: exact.id, channelName, categoryName };

        const fallback = cache.text.find((channel) => channel.name.toLowerCase() === channelName);
        if (fallback && this.categoryConfig.autoMoveExisting !== false) {
            await this.request('PATCH', `/channels/${fallback.id}`, { parent_id: parentId });
            fallback.parentId = parentId;
            return { id: fallback.id, channelName, categoryName };
        }

        const topicMaker = maker ? `Maker: ${sanitizeCategoryName(maker, 'Onbekend')}. ` : '';
        const created = await this.request('POST', `/guilds/${encodeURIComponent(guildId)}/channels`, {
            name: channelName,
            type: 0,
            parent_id: parentId,
            topic: truncate(`${topicMaker}Automatisch beheerd door de officiele Rico Scripts logging bot.`, 1024)
        });

        if (!created?.id) throw new Error(`Discord kanaal ${channelName} kon niet worden aangemaakt.`);
        const entry = { id: String(created.id), name: channelName, parentId };
        cache.text.push(entry);
        return { id: entry.id, channelName, categoryName };
    }

    buildEmbed(resourceName, payload = {}, maker = '') {
        const logType = String(payload.type || payload.level || 'info').toLowerCase();
        const fields = normalizeFields(payload.fields, 16);
        const player = payload.player && typeof payload.player === 'object' ? payload.player : null;

        if (player) {
            fields.unshift({
                name: 'Speler',
                value: `${truncate(player.name || 'Onbekend', 80)} (\`${truncate(player.source || '?', 16)}\`)`,
                inline: true
            });

            const identifiers = player.identifiers && typeof player.identifiers === 'object' ? player.identifiers : {};
            if (identifiers.discord) fields.push({ name: 'Discord', value: `<@${truncate(identifiers.discord, 32)}>`, inline: true });
            if (identifiers.license) fields.push({ name: 'License', value: `\`license:${truncate(identifiers.license, 64)}\``, inline: false });
            if (identifiers.fivem) fields.push({ name: 'FiveM', value: `\`fivem:${truncate(identifiers.fivem, 64)}\``, inline: true });
        }

        const categoryName = this.categoryForResource(resourceName, maker);
        fields.push({ name: 'Resource', value: `\`${truncate(resourceName || 'unknown', 90)}\``, inline: true });
        fields.push({ name: 'Maker', value: `\`${truncate(maker || 'Onbekend', 90)}\``, inline: true });
        fields.push({ name: 'Categorie', value: `\`${truncate(categoryName, 90)}\``, inline: true });
        fields.push({ name: 'Type', value: `\`${truncate(logType, 50)}\``, inline: true });

        const embed = {
            title: truncate(payload.title || 'FiveM log', 256),
            description: payload.description ? truncate(payload.description, 4096) : undefined,
            color: Number.isFinite(Number(payload.color)) ? Number(payload.color) : (COLORS[logType] || COLORS.info),
            fields: normalizeFields(fields, 25),
            timestamp: new Date().toISOString(),
            footer: { text: truncate(payload.footer || 'Rico Scripts • FiveM Logs', 2048) }
        };

        const thumbnail = validImageUrl(payload.thumbnail);
        const image = validImageUrl(payload.image);
        if (thumbnail) embed.thumbnail = { url: thumbnail };
        if (image) embed.image = { url: image };
        return embed;
    }

    async sendLog(guildId, resourceName, payload, maker = '') {
        const target = await this.ensureChannel(guildId, resourceName, maker);
        const embed = this.buildEmbed(resourceName, payload, maker);
        await this.request('POST', `/channels/${target.id}/messages`, {
            embeds: [embed],
            allowed_mentions: { parse: [] }
        });
        return target;
    }
}

export { DEFAULT_CATEGORY_CONFIG };
