const { onCall, HttpsError } = require('firebase-functions/v2/https');
const { onRequest } = require('firebase-functions/v2/https');
const { onDocumentWritten, onDocumentCreated } = require('firebase-functions/v2/firestore');
const { onSchedule } = require('firebase-functions/v2/scheduler');
const { defineSecret } = require('firebase-functions/params');
const admin = require('firebase-admin');
const crypto = require('crypto');
const rules = require('./rules');
const payments = require('./payments');

const RAZORPAY_KEY_ID = defineSecret('RAZORPAY_KEY_ID');
const RAZORPAY_KEY_SECRET = defineSecret('RAZORPAY_KEY_SECRET');
const RAZORPAY_WEBHOOK_SECRET = defineSecret('RAZORPAY_WEBHOOK_SECRET');

admin.initializeApp();
const db = admin.firestore();
const { FieldValue } = admin.firestore;

async function loadConfig() {
  const snap = await db.doc('config/funding').get();
  return { ...rules.DEFAULT_CONFIG, ...(snap.exists ? snap.data() : {}) };
}

async function loadCategory(id) {
  const snap = await db.doc(`categories/${id}`).get();
  if (!snap.exists) throw new HttpsError('invalid-argument', `Unknown category ${id}`);
  return snap.data();
}

function requireAuth(req) {
  if (!req.auth) throw new HttpsError('unauthenticated', 'Sign in required');
  return req.auth.uid;
}

function requireAdmin(req) {
  requireAuth(req);
  if (req.auth.token.admin !== true) throw new HttpsError('permission-denied', 'Admin only');
}

// Bills are only created through this callable; Firestore rules deny direct client writes.
exports.submitBill = onCall({ enforceAppCheck: false }, async (req) => {
  const uid = requireAuth(req);
  const d = req.data || {};
  const config = await loadConfig();

  const amount = Number(d.amount);
  const currency = String(d.currency || 'INR');
  if (!Number.isFinite(amount) || amount <= 0) throw new HttpsError('invalid-argument', 'Amount must be positive');
  if (amount > (config.maxBillAmount[currency] || Infinity)) throw new HttpsError('invalid-argument', 'Amount exceeds limit');
  if (!d.receiptImagePath || !String(d.receiptImagePath).startsWith(`receipts/${uid}/`)) {
    throw new HttpsError('invalid-argument', 'Receipt must be uploaded to your own folder');
  }

  const sub = await loadCategory(d.subcategoryId || d.categoryId);
  const categoryId = sub.parentCategoryId || sub.categoryId;
  const category = sub.parentCategoryId ? await loadCategory(categoryId) : sub;
  if (!category.isActive || !sub.isActive) throw new HttpsError('failed-precondition', 'Category is disabled');

  // Duplicate detection: exact image hash, plus same merchant/amount/date fingerprint.
  const [file] = await admin.storage().bucket().file(d.receiptImagePath).download();
  const imageHash = crypto.createHash('sha256').update(file).digest('hex');
  const fingerprint = crypto.createHash('sha256')
    .update(`${String(d.merchantName || '').trim().toLowerCase()}|${amount}|${d.billDate || ''}`).digest('hex');
  const [byImage, byPrint] = await Promise.all([
    db.collection('receiptHashes').doc(imageHash).get(),
    db.collection('receiptHashes').doc(`fp_${fingerprint}`).get(),
  ]);
  const duplicateFound = byImage.exists || byPrint.exists;

  const billRef = db.collection('bills').doc();
  const bill = {
    billId: billRef.id,
    userId: uid,
    merchantName: String(d.merchantName || '').slice(0, 120),
    categoryId,
    subcategoryId: sub.parentCategoryId ? sub.categoryId : null,
    billTypeId: d.billTypeId || null,
    classification: sub.classification,
    amount,
    currency,
    billDate: d.billDate || null,
    region: d.region || null,
    city: d.city || null,
    urgency: ['low', 'medium', 'high', 'critical'].includes(d.urgency) ? d.urgency : 'medium',
    receiptImageUrl: d.receiptImagePath, // served via signed URL / redacted copy only
    fundingPurpose: rules.redact(String(d.fundingPurpose || '').slice(0, 500)),
    ocr: d.ocr ? { ...d.ocr, rawText: rules.redact(d.ocr.rawText || '') } : null,
    imageMetadata: d.imageMetadata || null,
    suggestedCategoryId: d.suggestedCategoryId || null,
    userCorrectedCategory: Boolean(d.suggestedCategoryId && d.suggestedCategoryId !== sub.categoryId),
    fundedAmount: 0,
    remainingAmount: amount,
    fundingStatus: 'open',
    reviewApproved: false,
    createdAt: FieldValue.serverTimestamp(),
  };
  const v = rules.verifyReceipt(bill, sub, { duplicateFound, config });
  bill.verificationStatus = v.verificationStatus;
  bill.verificationFlags = v.flags;
  const e = rules.billEligibility(bill, sub, config);
  bill.fundingEligibility = e.fundingEligibility;
  bill.eligibilityReasons = e.reasons;
  if (v.verificationStatus === 'rejected') bill.fundingStatus = 'closed';

  const batch = db.batch();
  batch.set(billRef, bill);
  if (!duplicateFound) {
    batch.set(db.collection('receiptHashes').doc(imageHash), { billId: billRef.id, uid });
    batch.set(db.collection('receiptHashes').doc(`fp_${fingerprint}`), { billId: billRef.id, uid });
  }
  await batch.commit();
  return { billId: billRef.id, verificationStatus: bill.verificationStatus, fundingEligibility: bill.fundingEligibility, flags: v.flags };
});

// Payments live in payments.js (data) and below in the "Payments" section.

// Moderator decision on bills awaiting review.
exports.reviewBill = onCall(async (req) => {
  requireAdmin(req);
  const { billId, approve, categoryId } = req.data || {};
  const ref = db.doc(`bills/${billId}`);
  const snap = await ref.get();
  if (!snap.exists) throw new HttpsError('not-found', 'Bill not found');
  const bill = snap.data();
  const cat = await loadCategory(categoryId || bill.subcategoryId || bill.categoryId);
  const updated = {
    ...bill,
    subcategoryId: cat.parentCategoryId ? cat.categoryId : null,
    categoryId: cat.parentCategoryId || cat.categoryId,
    classification: cat.classification,
    reviewApproved: Boolean(approve),
    verificationStatus: approve ? 'verified' : 'rejected',
  };
  const e = rules.billEligibility(updated, cat, await loadConfig());
  await ref.update({
    subcategoryId: updated.subcategoryId, categoryId: updated.categoryId, classification: updated.classification,
    reviewApproved: updated.reviewApproved, verificationStatus: updated.verificationStatus,
    fundingEligibility: e.fundingEligibility, eligibilityReasons: e.reasons,
    fundingStatus: approve ? bill.fundingStatus : 'closed',
    reviewedBy: req.auth.uid, reviewedAt: FieldValue.serverTimestamp(),
  });
  return e;
});

// Admin category management: create / edit / disable / reorder / merge, without an app release.
const EDITABLE = ['categoryName', 'localizedNames', 'description', 'icon', 'isActive', 'requiresAgeVerification',
  'requiresManualReview', 'fundingEligibility', 'classification', 'displayOrder', 'parentCategoryId', 'legalJurisdictionsOnly'];

exports.upsertCategory = onCall(async (req) => {
  requireAdmin(req);
  const c = req.data || {};
  if (!/^[a-z0-9_.]+$/.test(c.categoryId || '')) throw new HttpsError('invalid-argument', 'Bad categoryId');
  if (c.fundingEligibility && !['eligible', 'review', 'restricted'].includes(c.fundingEligibility)) {
    throw new HttpsError('invalid-argument', 'Bad fundingEligibility');
  }
  const data = Object.fromEntries(EDITABLE.filter((k) => k in c).map((k) => [k, c[k]]));
  data.updatedAt = FieldValue.serverTimestamp();
  await db.doc(`categories/${c.categoryId}`).set({ categoryId: c.categoryId, ...data }, { merge: true });
  await db.doc('config/categoriesVersion').set({ version: FieldValue.increment(1) }, { merge: true });
  return { ok: true };
});

exports.reorderCategories = onCall(async (req) => {
  requireAdmin(req);
  const ids = (req.data && req.data.orderedIds) || [];
  const batch = db.batch();
  ids.forEach((id, i) => batch.update(db.doc(`categories/${id}`), { displayOrder: (i + 1) * 10 }));
  batch.set(db.doc('config/categoriesVersion'), { version: FieldValue.increment(1) }, { merge: true });
  await batch.commit();
  return { ok: true };
});

// Moves bills (and child categories) from `fromId` to `intoId`, then disables `fromId`.
exports.mergeCategories = onCall({ timeoutSeconds: 540 }, async (req) => {
  requireAdmin(req);
  const { fromId, intoId } = req.data || {};
  const into = await loadCategory(intoId);
  await loadCategory(fromId);
  const intoRoot = into.parentCategoryId || into.categoryId;
  let moved = 0;
  for (const field of ['categoryId', 'subcategoryId']) {
    let q = await db.collection('bills').where(field, '==', fromId).limit(400).get();
    while (!q.empty) {
      const batch = db.batch();
      q.docs.forEach((d) => batch.update(d.ref, into.parentCategoryId
        ? { categoryId: intoRoot, subcategoryId: intoId }
        : { categoryId: intoId, subcategoryId: null }));
      await batch.commit();
      moved += q.size;
      q = await db.collection('bills').where(field, '==', fromId).limit(400).get();
    }
  }
  const children = await db.collection('categories').where('parentCategoryId', '==', fromId).get();
  const batch = db.batch();
  children.docs.forEach((d) => batch.update(d.ref, { parentCategoryId: intoId }));
  batch.update(db.doc(`categories/${fromId}`), { isActive: false, mergedInto: intoId });
  batch.set(db.doc('config/categoriesVersion'), { version: FieldValue.increment(1) }, { merge: true });
  await batch.commit();
  return { moved };
});

// Analytics: maintain per-category and global aggregates as bills/donations change.
exports.onBillWritten = onDocumentWritten('bills/{billId}', async (event) => {
  const before = event.data.before.exists ? event.data.before.data() : null;
  const after = event.data.after.exists ? event.data.after.data() : null;
  const updates = [];
  const bump = (bill, sign) => {
    if (!bill) return;
    const funded = bill.fundingStatus === 'funded' ? 1 : 0;
    const fields = {
      uploadedBills: FieldValue.increment(sign),
      requestedAmount: FieldValue.increment(sign * bill.amount),
      fundedAmount: FieldValue.increment(sign * (bill.fundedAmount || 0)),
      fullyFundedBills: FieldValue.increment(sign * funded),
    };
    updates.push(db.doc(`analytics/category_${bill.categoryId}`).set({ categoryId: bill.categoryId, ...fields }, { merge: true }));
    updates.push(db.doc('analytics/global').set(fields, { merge: true }));
  };
  bump(before, -1);
  bump(after, 1);
  await Promise.all(updates);
});

// ───────────────────────────── Payments ─────────────────────────────
// Flow: getCheckout → createPaymentOrder → provider checkout in the app →
// provider webhook (signed) → applyDonation. The client never marks anything paid.

async function loadDonorAndBill(uid, billId) {
  const [billSnap, donorSnap] = await Promise.all([db.doc(`bills/${billId}`).get(), db.doc(`donors/${uid}`).get()]);
  if (!billSnap.exists) throw new HttpsError('not-found', 'Bill not found');
  const bill = billSnap.data();
  const cat = await loadCategory(bill.subcategoryId || bill.categoryId);
  return { bill, cat, donor: donorSnap.exists ? donorSnap.data() : {} };
}

// Personalised pay sheet: ranked methods + quick amounts for this donor and bill.
exports.getCheckout = onCall(async (req) => {
  const uid = requireAuth(req);
  const { billId, amount } = req.data || {};
  const { bill, cat, donor } = await loadDonorAndBill(uid, billId);
  const check = rules.donorCanFund(bill, cat, donor, await loadConfig());
  if (!check.allowed) throw new HttpsError('failed-precondition', check.reason);
  const global = (await db.doc('analytics/paymentMethods').get()).data() || {};
  const amounts = payments.suggestAmounts(donor.paymentProfile, bill.remainingAmount);
  const forAmount = Number(amount) > 0 ? Math.min(Number(amount), bill.remainingAmount) : amounts.defaultAmount;
  return {
    amounts,
    methods: payments.recommendMethods(donor.paymentProfile, global.stats || {}, forAmount),
  };
});

exports.createPaymentOrder = onCall({ secrets: [RAZORPAY_KEY_ID, RAZORPAY_KEY_SECRET] }, async (req) => {
  const uid = requireAuth(req);
  const { billId, method } = req.data || {};
  const amount = Math.round(Number(req.data && req.data.amount));
  if (!payments.METHODS[method]) throw new HttpsError('invalid-argument', 'Unknown payment method');
  if (!Number.isFinite(amount) || amount < 1) throw new HttpsError('invalid-argument', 'Bad amount');
  if (amount > payments.METHODS[method].maxAmount) throw new HttpsError('invalid-argument', 'Amount above method limit');
  const { bill, cat, donor } = await loadDonorAndBill(uid, billId);
  if (bill.userId === uid) throw new HttpsError('failed-precondition', 'Cannot fund your own bill');
  const check = rules.donorCanFund(bill, cat, donor, await loadConfig());
  if (!check.allowed) throw new HttpsError('failed-precondition', check.reason);
  if (amount > bill.remainingAmount) throw new HttpsError('invalid-argument', 'More than the amount left');

  const ref = db.collection('payments').doc();
  const res = await fetch('https://api.razorpay.com/v1/orders', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      Authorization: 'Basic ' + Buffer.from(`${RAZORPAY_KEY_ID.value()}:${RAZORPAY_KEY_SECRET.value()}`).toString('base64'),
    },
    body: JSON.stringify({ amount: amount * 100, currency: bill.currency, receipt: ref.id, notes: { paymentId: ref.id, billId } }),
  });
  if (!res.ok) throw new HttpsError('unavailable', 'Payment provider unavailable, please retry');
  const order = await res.json();
  const now = Date.now();
  await ref.set({
    paymentId: ref.id, uid, billId, amount, currency: bill.currency, method, status: 'created',
    providerOrderId: order.id, createdAt: now, consumed: false,
  });
  await logPaymentEvent({ paymentId: ref.id, uid, billId, method, amount, status: 'created', at: now });
  return { paymentId: ref.id, orderId: order.id, keyId: RAZORPAY_KEY_ID.value(), amountPaise: amount * 100, currency: bill.currency };
});

function logPaymentEvent(e) {
  return db.collection('paymentEvents').add({ ...e, categoryId: e.categoryId || null });
}

// Provider → us. Only a correctly signed request can mark a payment captured.
exports.razorpayWebhook = onRequest({ secrets: [RAZORPAY_WEBHOOK_SECRET] }, async (req, res) => {
  const expected = crypto.createHmac('sha256', RAZORPAY_WEBHOOK_SECRET.value()).update(req.rawBody).digest('hex');
  const given = String(req.get('X-Razorpay-Signature') || '');
  if (given.length !== expected.length || !crypto.timingSafeEqual(Buffer.from(given), Buffer.from(expected))) {
    res.status(401).send('bad signature');
    return;
  }
  const { event, payload } = req.body;
  const p = payload && payload.payment && payload.payment.entity;
  const paymentId = p && p.notes && p.notes.paymentId;
  if (!paymentId) { res.status(200).send('ignored'); return; }
  const ref = db.doc(`payments/${paymentId}`);
  const snap = await ref.get();
  if (!snap.exists || snap.data().providerOrderId !== p.order_id) { res.status(200).send('unknown'); return; }
  const pay = snap.data();
  const method = payments.METHODS[p.method] ? p.method : pay.method; // what the donor actually used
  const now = Date.now();
  if (event === 'payment.captured') {
    if (p.amount !== pay.amount * 100) { res.status(400).send('amount mismatch'); return; }
    await applyDonation(paymentId, { method, providerPaymentId: p.id });
    await logPaymentEvent({ paymentId, uid: pay.uid, billId: pay.billId, method, amount: pay.amount, status: 'captured', at: now });
  } else if (event === 'payment.failed') {
    await ref.update({ status: 'failed', failureReason: p.error_reason || null, updatedAt: now });
    await logPaymentEvent({ paymentId, uid: pay.uid, billId: pay.billId, method, amount: pay.amount, status: 'failed', at: now });
  }
  res.status(200).send('ok');
});

// Idempotent: a payment is applied to its bill exactly once. If the bill filled up meanwhile,
// the excess is marked for refund instead of being kept.
async function applyDonation(paymentId, { method, providerPaymentId }) {
  const config = await loadConfig();
  return db.runTransaction(async (tx) => {
    const payRef = db.doc(`payments/${paymentId}`);
    const pay = (await tx.get(payRef)).data();
    if (pay.consumed) return;
    const billRef = db.doc(`bills/${pay.billId}`);
    const bill = (await tx.get(billRef)).data();
    const cat = (await tx.get(db.doc(`categories/${bill.subcategoryId || bill.categoryId}`))).data();
    const donorSnap = await tx.get(db.doc(`donors/${pay.uid}`));
    const check = rules.donorCanFund(bill, cat, donorSnap.exists ? donorSnap.data() : {}, config);
    const applied = check.allowed ? Math.min(pay.amount, bill.remainingAmount) : 0;
    const refund = pay.amount - applied;
    const remaining = bill.remainingAmount - applied;
    if (applied > 0) {
      tx.update(billRef, {
        fundedAmount: FieldValue.increment(applied),
        remainingAmount: remaining,
        fundingStatus: remaining <= 0 ? 'funded' : 'partially_funded',
      });
      tx.set(db.collection('donations').doc(paymentId), {
        billId: pay.billId, donorId: pay.uid, amount: applied, currency: pay.currency, categoryId: bill.categoryId,
        method, createdAt: FieldValue.serverTimestamp(),
      });
    }
    if (remaining <= 0 && applied > 0) {
      // Funds go to the merchant / verified beneficiary, never to the uploader's personal account.
      tx.set(db.doc(`payouts/${pay.billId}`), {
        billId: pay.billId, amount: bill.amount, currency: pay.currency, payee: bill.merchantName,
        status: 'pending_beneficiary_verification', createdAt: FieldValue.serverTimestamp(),
      });
    }
    tx.update(payRef, {
      status: 'captured', consumed: true, applied, refundDue: refund, method, providerPaymentId,
      refundReason: refund > 0 ? (check.allowed ? 'bill_already_funded' : check.reason) : null,
      updatedAt: Date.now(),
    });
  });
}

// Lets the app show the result as soon as the webhook lands.
exports.getPaymentStatus = onCall(async (req) => {
  const uid = requireAuth(req);
  const snap = await db.doc(`payments/${req.data && req.data.paymentId}`).get();
  if (!snap.exists || snap.data().uid !== uid) throw new HttpsError('not-found', 'Payment not found');
  const { status, applied, refundDue } = snap.data();
  const bill = (await db.doc(`bills/${snap.data().billId}`).get()).data();
  return { status, applied: applied || 0, refundDue: refundDue || 0, remainingAmount: bill.remainingAmount };
});

// ─────────────────────── Payment data pipeline ───────────────────────

// Incremental: refresh this donor's features whenever one of their payments reaches a final state.
exports.onPaymentEvent = onDocumentCreated('paymentEvents/{id}', async (event) => {
  const e = event.data.data();
  if (!['captured', 'failed', 'abandoned'].includes(e.status)) return;
  const recent = await db.collection('paymentEvents').where('uid', '==', e.uid)
    .orderBy('at', 'desc').limit(500).get();
  const profile = payments.buildDonorProfile(recent.docs.map((d) => d.data()));
  await db.doc(`donors/${e.uid}`).set({ paymentProfile: profile }, { merge: true });
});

// Nightly batch: platform-wide success rates per method × amount over the last 30 days,
// and close out checkouts the donor never finished so they count as abandoned.
exports.nightlyPaymentStats = onSchedule({ schedule: '17 2 * * *', timeZone: 'Asia/Kolkata' }, async () => {
  const now = Date.now();
  const stale = await db.collection('payments').where('status', '==', 'created')
    .where('createdAt', '<', now - 30 * 60 * 1000).limit(2000).get();
  for (const d of stale.docs) {
    const p = d.data();
    await d.ref.update({ status: 'abandoned', updatedAt: now });
    await logPaymentEvent({ paymentId: p.paymentId, uid: p.uid, billId: p.billId, method: p.method, amount: p.amount, status: 'abandoned', at: now });
  }
  const since = now - 30 * 86400000;
  const rows = [];
  let q = db.collection('paymentEvents').where('at', '>=', since).orderBy('at').limit(5000);
  for (;;) {
    const page = await q.get();
    page.docs.forEach((d) => rows.push(d.data()));
    if (page.size < 5000) break;
    q = q.startAfter(page.docs[page.docs.length - 1]);
  }
  await db.doc('analytics/paymentMethods').set({ stats: payments.buildGlobalStats(rows), windowDays: 30, events: rows.length, updatedAt: now });
});
