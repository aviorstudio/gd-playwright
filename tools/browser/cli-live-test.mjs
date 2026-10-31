import assert from 'node:assert/strict';
import { execFile } from 'node:child_process';
import { createServer } from 'node:net';
import { resolve } from 'node:path';
import { promisify } from 'node:util';
import { chromium } from 'playwright';

const exec = promisify(execFile);
const binary = resolve('.artifacts/bin/gdpw');
const listener = createServer();
await new Promise(resolve => listener.listen(0, '127.0.0.1', resolve));
const port = listener.address().port;
await new Promise(resolve => listener.close(resolve));
const browser = await chromium.launch({ headless: true, chromiumSandbox: process.getuid?.() !== 0, args: [`--remote-debugging-port=${port}`] });
try {
  const unrelated = await browser.newPage();
  await unrelated.goto('about:blank');
  const page = await browser.newPage();
  await page.goto(`http://127.0.0.1:${process.argv[2]}/diagnostic/index.html`);
  await page.waitForFunction(() => window.godotTestState?.fixture?.cleanup === true);
  const run = async (...args) => {
    const result = await exec(binary, [...args, '--port', String(port)], { timeout: 10000 });
    return result.stdout.trim();
  };
  const state = JSON.parse(await run('state'));
  assert.equal(state.test_state.fixture.route, 'diagnostic');
  assert.equal(state.elements.total, 1);
  const position = JSON.parse(await run('get', 'start_button', '--json'));
  const expected = await page.evaluate(() => {
    const element = window.godotElements.start_button;
    const viewport = window.godotElementsViewport;
    const canvas = document.querySelector('canvas').getBoundingClientRect();
    return { x: Math.round(canvas.x + element.x * canvas.width / viewport.width), y: Math.round(canvas.y + element.y * canvas.height / viewport.height) };
  });
  assert.equal(position.x, expected.x);
  assert.equal(position.y, expected.y);
  assert.equal(await run('list', '--visible'), 'start_button');
  assert.equal(JSON.parse(await run('events', '--name', 'route_loaded'))[0].data.route, 'diagnostic');
  assert.equal(JSON.parse(await run('wait', 'route_loaded', '--include-past', '--timeout', '1000')).data.route, 'diagnostic');
  const missing = exec(binary, ['wait', 'missing', '--port', String(port), '--timeout', '50'], { timeout: 10000 });
  await assert.rejects(missing, error => error.code === 1 && error.stderr.includes('timeout waiting for event'));
  assert.equal(await page.evaluate(() => window.godotTestState.fixture.input), false);
  const generated = await run('get', 'start_button', '--script');
  assert(generated.startsWith('playwright-cli run-code '));
  assert.equal(await page.evaluate(() => window.godotTestState.fixture.input), false);
  console.log('ASSERTION_REACHED Rust gdpw reads live diagnostic export without input');
} finally {
  await browser.close();
}
