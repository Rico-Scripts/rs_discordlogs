import assert from 'node:assert/strict';
import { DiscordService, DEFAULT_CATEGORY_CONFIG } from '../src/discord.js';

const service = new DiscordService({
    token: 'test-token',
    categoryConfig: DEFAULT_CATEGORY_CONFIG
});

assert.equal(service.categoryForResource('rs_phone', 'Rico-Scripts'), 'Rico-Scripts');
assert.equal(service.categoryForResource('ox_inventory', 'overextended'), 'overextended');
assert.equal(service.categoryForResource('jobs_creator', 'jaksam1074'), 'jaksam1074');
assert.equal(service.categoryForResource('unknown_script', ''), 'Onbekende Scripts');
assert.equal(service.categoryForResource('connections', 'Whatever Author'), 'Algemene Logs');
assert.equal(service.categoryForResource('server', ''), 'Algemene Logs');
assert.deepEqual(service.configuredCategories(), []);

console.log('Author category routing OK');
