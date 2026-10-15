import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { parseInvitation } from '../parser.mjs';
import { allowedOrigins } from '../config.mjs';
const origins = ['https://invite.test'];
test('strict HTTPS origin and six ASCII code contract', () => {
  for (const url of ['https://invite.test/join/ABC234', 'https://invite.test:443/join/abc234']) {
    assert.equal(parseInvitation(url, origins), 'ABC234');
  }
  for (const url of ['http://invite.test/join/ABC234', 'https://else.test/join/ABC234',
    'https://u:p@invite.test/join/ABC234', 'https://@invite.test/join/ABC234', 'https://invite.test:444/join/ABC234',
    'https://invite.test/join/ABC234?', 'https://invite.test/join/ABC234#',
    'https://invite.test/join/ABC234/', 'https://invite.test/join/%41BC234',
    'https://invite.test/join/ABC23I', 'https://invite.test/join/ABC230',
    'https://invite.test/a/../join/ABC234', 'https://invite.test/join/ＡBC234']) {
    assert.equal(parseInvitation(url, origins), null, url);
  }
  assert.equal(parseInvitation('https://invite.test/join/ABC234', allowedOrigins), null);
});
test('actual landing DOM writes only a validated code and safe local reopen', async () => {
  const elements = Object.fromEntries(['room-code','status','reopen','install'].map(id => [id, { hidden:true }]));
  globalThis.window = { location: { href:'https://invite.test/join/ABC234' } };
  globalThis.document = { getElementById:id => elements[id] };
  await import('../landing.mjs');
  assert.equal(elements['room-code'].hidden,true);
  assert.match(elements.status.textContent,/not supported/);
  assert.equal(elements.reopen.href,undefined);
  delete globalThis.window; delete globalThis.document;
});
test('assets contain no external resource, analytics or preview API and retain security policy', async () => {
  const html=await readFile(new URL('../index.html',import.meta.url),'utf8');
  assert.match(html,/name="referrer" content="no-referrer"/);
  assert.match(html,/connect-src 'none'/);
  assert.doesNotMatch(html,/https?:\/\//);
  assert.match(html,/reopen the link/);
  const landing=await readFile(new URL('../landing.mjs',import.meta.url),'utf8');
  assert.doesNotMatch(landing,/fetch\(|XMLHttpRequest|innerHTML|sendBeacon/);
});
test('configured landing exposes canonical code, installation guidance and same original reopen', async () => {
  const { renderInvitation } = await import('../landing.mjs');
  const elements = Object.fromEntries(['room-code','status','reopen','install'].map(id => [id, {
    hidden:true, setAttribute(key,value) { this[key]=value; }
  }]));
  const document = { getElementById:id => elements[id] };
  renderInvitation(document,'https://invite.test/join/abc234',origins,null);
  assert.equal(elements['room-code'].textContent,'ABC234');
  assert.equal(elements['room-code']['aria-label'],'Room code A B C 2 3 4');
  assert.equal(elements.reopen.href,'https://invite.test/join/abc234');
  assert.equal(elements.install.hidden,true,'No guessed App Store URL');
  assert.match(elements.status.textContent,/reopen this same invitation/);
  assert.match(elements.status.textContent,/enter this code/);
  assert.doesNotMatch(elements.status.textContent,/automatically|deferred/);
});
