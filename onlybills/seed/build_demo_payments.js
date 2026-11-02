// Generates assets/demo/payments.json for demo mode:
//   globalStats  - output of the nightly pipeline over a synthetic 30-day event log
//   donorEvents  - the demo donor's own payment history (the app rebuilds the profile from it)
// Synthetic rates mimic typical patterns: UPI is great for small amounts but fails more on large ones.
const fs = require('fs');
const path = require('path');
const p = require('../functions/payments');

let seed = 42;
const rand = () => ((seed = (seed * 1103515245 + 12345) % 2147483648) / 2147483648);

const TRUE_RATE = {
  upi: { xs: 0.95, s: 0.93, m: 0.88, l: 0.72, xl: 0.6 },
  card: { xs: 0.84, s: 0.85, m: 0.86, l: 0.85, xl: 0.83 },
  netbanking: { xs: 0.78, s: 0.8, m: 0.84, l: 0.9, xl: 0.92 },
  wallet: { xs: 0.9, s: 0.88, m: 0.8, l: 0.7, xl: 0.6 },
};
const MIX = [['upi', 0.62], ['card', 0.2], ['netbanking', 0.1], ['wallet', 0.08]];
const pick = () => { let r = rand(); for (const [m, w] of MIX) { if ((r -= w) <= 0) return m; } return 'upi'; };
const amount = () => Math.round(Math.exp(4 + rand() * 7)); // ~₹55 to ~₹60,000, skewed small

const now = Date.UTC(2026, 10, 1);
const platform = [];
for (let i = 0; i < 6000; i++) {
  const method = pick();
  const amt = Math.min(amount(), p.METHODS[method].maxAmount);
  const r = rand();
  const ok = TRUE_RATE[method][p.bucketOf(amt)];
  const status = r < ok ? 'captured' : r < ok + (1 - ok) * 0.6 ? 'failed' : 'abandoned';
  platform.push({ paymentId: `g${i}`, method, amount: amt, status, at: now - Math.floor(rand() * 30 * 86400000) });
}

// Demo donor: gives ~₹500-1000, usually by UPI; one large UPI payment failed, then card worked.
const day = 86400000;
const donorEvents = [
  ['upi', 500, 'captured', 60], ['upi', 1000, 'captured', 45], ['upi', 500, 'captured', 31],
  ['upi', 12000, 'failed', 20], ['card', 12000, 'captured', 20], ['upi', 750, 'captured', 12],
  ['wallet', 300, 'abandoned', 6], ['upi', 1000, 'captured', 3],
].map(([method, amt, status, ago], i) => ({ paymentId: `d${i}`, method, amount: amt, status, at: now - ago * day }));

const out = { generatedAt: now, globalStats: p.buildGlobalStats(platform), platformEvents: platform.length, donorEvents };
fs.writeFileSync(path.join(__dirname, '..', 'assets', 'demo', 'payments.json'), JSON.stringify(out, null, 1));

const prof = p.buildDonorProfile(donorEvents, now);
console.log('profile median', prof.medianAmount, 'p75', prof.p75Amount, 'last', prof.lastMethod);
for (const amt of [500, 1500, 20000, 60000]) {
  console.log(String(amt).padStart(6), p.recommendMethods(prof, out.globalStats, amt).map((m) => `${m.method}:${m.expectedSuccess.toFixed(2)}`).join('  '));
}
console.log('new donor @20000', p.recommendMethods(null, out.globalStats, 20000).map((m) => m.method).join(' > '));
