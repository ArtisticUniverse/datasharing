// End-to-end payment settlement against the Firestore emulator.
//   cd onlybills && npx firebase-tools emulators:exec --only firestore "node functions/integration/payments.emulator.js"
// The payment provider is faked: fetch() returns an order, and webhooks are signed with a test secret.
const assert = require('node:assert');
const crypto = require('crypto');

process.env.GCLOUD_PROJECT = 'demo-onlybills';
process.env.RAZORPAY_KEY_ID = 'rzp_test_key';
process.env.RAZORPAY_KEY_SECRET = 'test_secret';
process.env.RAZORPAY_WEBHOOK_SECRET = 'whsec_test';
assert.ok(process.env.FIRESTORE_EMULATOR_HOST, 'Run inside the Firestore emulator');

let orderSeq = 0;
global.fetch = async () => ({ ok: true, json: async () => ({ id: `order_${++orderSeq}` }) });

const fns = require('../index.js');
const admin = require('firebase-admin');
const db = admin.firestore();
const { build } = require('../../seed/build_seed');

const donor = { uid: 'donor1', token: {} };

function webhook(event, entity, secret = 'whsec_test') {
  const body = { event, payload: { payment: { entity } } };
  const raw = Buffer.from(JSON.stringify(body));
  const sig = crypto.createHmac('sha256', secret).update(raw).digest('hex');
  return new Promise((resolve) => {
    const res = { code: 200, status(c) { this.code = c; return this; }, send(m) { resolve({ code: this.code, msg: m }); } };
    fns.razorpayWebhook({ rawBody: raw, body, get: (h) => (h === 'X-Razorpay-Signature' ? sig : undefined), headers: {} }, res);
  });
}

async function order(amount, method = 'upi') {
  return fns.createPaymentOrder.run({ auth: donor, data: { billId: 'b1', amount, method }, rawRequest: {} });
}

(async () => {
  const cats = build().filter((c) => c.categoryId.startsWith('healthcare'));
  await Promise.all(cats.map((c) => db.doc(`categories/${c.categoryId}`).set(c)));
  await db.doc('bills/b1').set({
    billId: 'b1', userId: 'uploader', merchantName: 'City Hospital', categoryId: 'healthcare',
    subcategoryId: 'healthcare.hospital_bills', amount: 1000, remainingAmount: 1000, fundedAmount: 0,
    currency: 'INR', verificationStatus: 'verified', fundingEligibility: 'eligible', reviewApproved: true, fundingStatus: 'open',
  });

  // Checkout plan for a donor with no history.
  const plan = await fns.getCheckout.run({ auth: donor, data: { billId: 'b1' }, rawRequest: {} });
  assert.strictEqual(plan.methods[0].method, 'upi');
  assert.deepStrictEqual(plan.amounts.amounts, [250, 500]);

  // Uploader can't pay their own bill; method limits enforced.
  await assert.rejects(fns.createPaymentOrder.run({ auth: { uid: 'uploader', token: {} }, data: { billId: 'b1', amount: 100, method: 'upi' }, rawRequest: {} }), /own bill/);
  await assert.rejects(order(1001), /More than the amount left/);

  // 1. Pay ₹600: order created, webhook captures it.
  const o1 = await order(600);
  const entity1 = { id: 'pay_1', order_id: o1.orderId, amount: 60000, method: 'upi', notes: { paymentId: o1.paymentId } };
  assert.strictEqual((await webhook('payment.captured', entity1, 'wrong_secret')).code, 401, 'forged webhook rejected');
  assert.strictEqual((await db.doc('bills/b1').get()).data().remainingAmount, 1000, 'nothing applied by forged webhook');
  assert.strictEqual((await webhook('payment.captured', { ...entity1, amount: 1 })).code, 400, 'amount mismatch rejected');
  assert.strictEqual((await webhook('payment.captured', entity1)).code, 200);
  let bill = (await db.doc('bills/b1').get()).data();
  assert.strictEqual(bill.remainingAmount, 400);
  assert.strictEqual(bill.fundingStatus, 'partially_funded');

  // 2. Replayed webhook: no double counting.
  await webhook('payment.captured', entity1);
  assert.strictEqual((await db.doc('bills/b1').get()).data().remainingAmount, 400, 'replay is idempotent');
  assert.strictEqual((await db.collection('donations').get()).size, 1);

  // 3. Another donor's ₹400 lands first; ours (₹400 ordered earlier) is now excess → refund.
  const o2 = await order(400);
  await db.doc('bills/b1').update({ remainingAmount: 150, fundedAmount: 850 }); // someone else paid ₹250 meanwhile
  await webhook('payment.captured', { id: 'pay_2', order_id: o2.orderId, amount: 40000, method: 'card', notes: { paymentId: o2.paymentId } });
  const p2 = (await db.doc(`payments/${o2.paymentId}`).get()).data();
  assert.strictEqual(p2.applied, 150);
  assert.strictEqual(p2.refundDue, 250);
  assert.strictEqual(p2.method, 'card', 'records the method actually used');
  bill = (await db.doc('bills/b1').get()).data();
  assert.strictEqual(bill.remainingAmount, 0);
  assert.strictEqual(bill.fundingStatus, 'funded');
  assert.strictEqual((await db.doc('payouts/b1').get()).data().status, 'pending_beneficiary_verification');

  // 4. Failed payment is recorded, not applied.
  await db.doc('bills/b1').update({ remainingAmount: 500, fundingStatus: 'partially_funded' });
  const o3 = await order(500);
  await webhook('payment.failed', { id: 'pay_3', order_id: o3.orderId, amount: 50000, method: 'upi', error_reason: 'payment_timed_out', notes: { paymentId: o3.paymentId } });
  assert.strictEqual((await db.doc(`payments/${o3.paymentId}`).get()).data().status, 'failed');
  assert.strictEqual((await db.doc('bills/b1').get()).data().remainingAmount, 500);

  // 5. Data pipeline: the event log rebuilds the donor profile.
  const events = await db.collection('paymentEvents').where('uid', '==', 'donor1').get();
  const last = events.docs.map((d) => d.data()).find((e) => e.status === 'failed');
  await fns.onPaymentEvent.run({ data: { data: () => last } });
  const profile = (await db.doc('donors/donor1').get()).data().paymentProfile;
  assert.strictEqual(profile.totalDonations, 2);
  assert.deepStrictEqual(profile.methodStats.upi, { attempts: 2, captured: 1, lastUsedAt: profile.methodStats.upi.lastUsedAt });
  assert.strictEqual(profile.lastMethod, 'card');

  // 6. Nightly job: abandoned checkouts and platform stats.
  await db.doc('payments/stale').set({ paymentId: 'stale', uid: 'donor1', billId: 'b1', amount: 100, method: 'wallet', status: 'created', createdAt: Date.now() - 3600e3 });
  await fns.nightlyPaymentStats.run({});
  assert.strictEqual((await db.doc('payments/stale').get()).data().status, 'abandoned');
  const stats = (await db.doc('analytics/paymentMethods').get()).data().stats;
  assert.deepStrictEqual(stats['upi:s'], { attempts: 2, captured: 1 }); // ₹600 captured + ₹500 failed
  assert.deepStrictEqual(stats['wallet:xs'], { attempts: 1, captured: 0 });

  console.log('payments emulator test: all checks passed');
  process.exit(0);
})().catch((e) => { console.error(e); process.exit(1); });
