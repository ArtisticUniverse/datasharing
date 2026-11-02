// Payment data pipeline + per-donor payment personalisation. Pure functions only:
// Cloud Functions feed them Firestore data, tests feed them fixtures.
//
// Data flow
//   paymentEvents/{id}      raw log: one row per attempt (created / captured / failed / abandoned)
//        │ buildGlobalStats()   nightly            → analytics/paymentMethods
//        │ buildDonorProfile()  on each event      → donors/{uid}.paymentProfile
//        ▼
//   recommendMethods() + suggestAmounts()  at checkout → one-tap pay sheet

const METHODS = {
  upi: { label: 'UPI', maxAmount: 100000, feePct: 0, feeFlat: 0 },
  card: { label: 'Debit / credit card', maxAmount: 500000, feePct: 2.0, feeFlat: 0 },
  netbanking: { label: 'Net banking', maxAmount: 500000, feePct: 1.9, feeFlat: 0 },
  wallet: { label: 'Wallet', maxAmount: 10000, feePct: 1.9, feeFlat: 0 },
};

// Amount buckets let success rates differ by size (large UPI payments fail more often, etc.).
const BUCKETS = [[0, 500, 'xs'], [500, 2000, 's'], [2000, 10000, 'm'], [10000, 50000, 'l'], [50000, Infinity, 'xl']];
const bucketOf = (amount) => BUCKETS.find(([lo, hi]) => amount >= lo && amount < hi)[2];

// Prior used when there is little data: roughly typical Indian success rates per method.
const PRIOR_SUCCESS = { upi: 0.9, card: 0.82, netbanking: 0.8, wallet: 0.85 };
const PRIOR_WEIGHT = 10; // a method needs ~10 attempts before its own data dominates

const FINAL = new Set(['captured', 'failed', 'abandoned']);

function fee(method, amount) {
  const m = METHODS[method];
  return Math.round((amount * m.feePct) / 100 + m.feeFlat);
}

function quantile(sorted, q) {
  if (!sorted.length) return null;
  const pos = (sorted.length - 1) * q;
  const lo = Math.floor(pos);
  const hi = Math.ceil(pos);
  return sorted[lo] + (sorted[hi] - sorted[lo]) * (pos - lo);
}

// Only the last state of each payment attempt counts (events can arrive out of order / twice).
function finalAttempts(events) {
  const byPayment = new Map();
  for (const e of events) {
    if (!FINAL.has(e.status) || !METHODS[e.method]) continue;
    const prev = byPayment.get(e.paymentId);
    if (!prev || e.at >= prev.at) byPayment.set(e.paymentId, e);
  }
  return [...byPayment.values()];
}

// Platform-wide success rate per method × amount bucket.
function buildGlobalStats(events) {
  const stats = {};
  for (const e of finalAttempts(events)) {
    const key = `${e.method}:${bucketOf(e.amount)}`;
    const s = (stats[key] ||= { attempts: 0, captured: 0 });
    s.attempts += 1;
    if (e.status === 'captured') s.captured += 1;
  }
  return stats;
}

// Smoothed success rate: blends observed data with a prior so small samples don't swing wildly.
function successRate(stats, method, bucket) {
  const s = (stats && stats[`${method}:${bucket}`]) || { attempts: 0, captured: 0 };
  return (s.captured + PRIOR_SUCCESS[method] * PRIOR_WEIGHT) / (s.attempts + PRIOR_WEIGHT);
}

// Per-donor features. Stored on the donor doc; contains no card or bank details.
function buildDonorProfile(events, now = Date.now()) {
  const attempts = finalAttempts(events).sort((a, b) => a.at - b.at);
  const captured = attempts.filter((e) => e.status === 'captured');
  const amounts = captured.map((e) => e.amount).sort((a, b) => a - b);
  const methodStats = {};
  for (const e of attempts) {
    const m = (methodStats[e.method] ||= { attempts: 0, captured: 0, lastUsedAt: 0 });
    m.attempts += 1;
    if (e.status === 'captured') m.captured += 1;
    m.lastUsedAt = Math.max(m.lastUsedAt, e.at);
  }
  // Per-donor stats in the same shape as global ones, so successRate() works on both.
  const bucketStats = buildGlobalStats(attempts);
  const lastCaptured = captured[captured.length - 1];
  const days = 86400000;
  const recent = captured.filter((e) => now - e.at < 90 * days);
  return {
    totalDonations: captured.length,
    totalAmount: amounts.reduce((a, b) => a + b, 0),
    medianAmount: quantile(amounts, 0.5),
    p75Amount: quantile(amounts, 0.75),
    lastMethod: lastCaptured ? lastCaptured.method : null,
    lastDonationAt: lastCaptured ? lastCaptured.at : null,
    donationsLast90Days: recent.length,
    methodStats,
    bucketStats,
    abandonRate: attempts.length ? attempts.filter((e) => e.status === 'abandoned').length / attempts.length : 0,
    updatedAt: now,
  };
}

// Ranks payment methods for this donor and this amount.
// Score = expected success (donor's own history, else platform data, else prior)
//       × familiarity boost (methods the donor already completed)
//       − fee penalty (fees reduce how much reaches the bill).
function recommendMethods(profile, globalStats, amount, { available = Object.keys(METHODS) } = {}) {
  const bucket = bucketOf(amount);
  const ranked = available
    .filter((m) => METHODS[m] && amount <= METHODS[m].maxAmount)
    .map((method) => {
      const platform = successRate(globalStats, method, bucket);
      const own = profile && profile.bucketStats ? profile.bucketStats[`${method}:${bucket}`] : null;
      // Donor's own record for this size of payment, shrunk toward the platform rate.
      const expected = own
        ? (own.captured + platform * PRIOR_WEIGHT) / (own.attempts + PRIOR_WEIGHT)
        : platform;
      const ms = profile && profile.methodStats ? profile.methodStats[method] : null;
      const familiar = ms && ms.captured > 0;
      const isLast = profile && profile.lastMethod === method;
      const feeAmt = fee(method, amount);
      const score = expected * (1 + (familiar ? 0.05 : 0) + (isLast ? 0.05 : 0)) - feeAmt / Math.max(amount, 1);
      const reasons = [];
      if (isLast) reasons.push('You used this last time');
      else if (familiar) reasons.push(`You've paid this way ${ms.captured}×`);
      if (feeAmt === 0) reasons.push('No fee');
      else reasons.push(`₹${feeAmt} fee`);
      reasons.push(`${Math.round(expected * 100)}% success for amounts like this`);
      return { method, label: METHODS[method].label, score, expectedSuccess: expected, fee: feeAmt, reasons };
    })
    .sort((a, b) => b.score - a.score);
  if (ranked.length) ranked[0].recommended = true;
  return ranked;
}

const NICE = [50, 100, 200, 250, 500, 1000, 1500, 2000, 2500, 5000, 10000, 25000, 50000];
const roundNice = (v) => NICE.reduce((best, n) => (Math.abs(n - v) < Math.abs(best - v) ? n : best), NICE[0]);

// Three quick-pick amounts around what this donor usually gives, plus "pay the rest".
function suggestAmounts(profile, remaining) {
  const base = profile && profile.medianAmount ? profile.medianAmount : 500;
  const high = profile && profile.p75Amount ? profile.p75Amount : base * 2;
  const picks = [...new Set([roundNice(base / 2), roundNice(base), roundNice(Math.max(high, base * 1.5))])]
    .filter((v) => v < remaining)
    .sort((a, b) => a - b);
  return { amounts: picks, payRemaining: remaining, defaultAmount: picks.includes(roundNice(base)) ? roundNice(base) : (picks[picks.length - 1] || remaining) };
}

module.exports = {
  METHODS, BUCKETS, PRIOR_SUCCESS, bucketOf, fee, finalAttempts, buildGlobalStats, successRate,
  buildDonorProfile, recommendMethods, suggestAmounts, roundNice,
};
