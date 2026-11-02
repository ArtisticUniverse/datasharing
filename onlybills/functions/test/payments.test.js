const test = require('node:test');
const assert = require('node:assert');
const p = require('../payments');

const ev = (paymentId, method, amount, status, at) => ({ paymentId, method, amount, status, at });

test('only the latest final state of each attempt counts', () => {
  const a = p.finalAttempts([ev('1', 'upi', 100, 'created', 1), ev('1', 'upi', 100, 'failed', 2), ev('1', 'upi', 100, 'captured', 3), ev('1', 'upi', 100, 'captured', 3)]);
  assert.strictEqual(a.length, 1);
  assert.strictEqual(a[0].status, 'captured');
});

test('global stats per method and amount bucket', () => {
  const s = p.buildGlobalStats([ev('1', 'upi', 100, 'captured', 1), ev('2', 'upi', 300, 'failed', 1), ev('3', 'card', 60000, 'captured', 1)]);
  assert.deepStrictEqual(s['upi:xs'], { attempts: 2, captured: 1 });
  assert.deepStrictEqual(s['card:xl'], { attempts: 1, captured: 1 });
});

test('donor profile', () => {
  const pr = p.buildDonorProfile([
    ev('1', 'card', 1000, 'captured', 1), ev('2', 'upi', 500, 'captured', 2), ev('3', 'upi', 2000, 'captured', 3), ev('4', 'wallet', 300, 'abandoned', 4),
  ], 5);
  assert.strictEqual(pr.totalDonations, 3);
  assert.strictEqual(pr.medianAmount, 1000);
  assert.strictEqual(pr.lastMethod, 'upi');
  assert.strictEqual(pr.abandonRate, 0.25);
});

test('new donor: UPI first (no fee, high success), wallet excluded above its limit', () => {
  const r = p.recommendMethods(null, {}, 20000);
  assert.strictEqual(r[0].method, 'upi');
  assert.ok(r[0].recommended);
  assert.ok(!r.some((x) => x.method === 'wallet'));
});

test('UPI is not offered above its per-transaction limit', () => {
  assert.ok(!p.recommendMethods(null, {}, 150000).some((x) => x.method === 'upi'));
});

test("a donor whose UPI keeps failing gets steered to the card they've used successfully", () => {
  const events = [];
  for (let i = 0; i < 8; i++) events.push(ev(`u${i}`, 'upi', 1500, 'failed', i));
  for (let i = 0; i < 6; i++) events.push(ev(`c${i}`, 'card', 1500, 'captured', 10 + i));
  const r = p.recommendMethods(p.buildDonorProfile(events, 20), {}, 1500);
  assert.strictEqual(r[0].method, 'card');
  assert.match(r[0].reasons[0], /last time/);
});

test('platform data moves the ranking for donors without history', () => {
  const g = {};
  g['upi:l'] = { attempts: 1000, captured: 550 };
  g['netbanking:l'] = { attempts: 1000, captured: 960 };
  assert.strictEqual(p.recommendMethods(null, g, 20000)[0].method, 'netbanking');
});

test('amount suggestions follow the donor and never exceed what is left', () => {
  const s = p.suggestAmounts({ medianAmount: 1000, p75Amount: 2000 }, 1800);
  assert.deepStrictEqual(s.amounts, [500, 1000]);
  assert.strictEqual(s.defaultAmount, 1000);
  assert.strictEqual(s.payRemaining, 1800);
  assert.deepStrictEqual(p.suggestAmounts(null, 5000).amounts, [250, 500, 1000]);
});
