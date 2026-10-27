const { onCall, HttpsError } = require('firebase-functions/v2/https');
const { onDocumentWritten } = require('firebase-functions/v2/firestore');
const admin = require('firebase-admin');
const crypto = require('crypto');
const rules = require('./rules');

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

// Donation is recorded atomically; payment capture happens with the provider before this call
// and the provider's payment id is verified by the webhook that sets payments/{id}.status = captured.
exports.fundBill = onCall(async (req) => {
  const uid = requireAuth(req);
  const { billId, amount, paymentId } = req.data || {};
  const amt = Number(amount);
  if (!billId || !Number.isFinite(amt) || amt <= 0) throw new HttpsError('invalid-argument', 'Bad request');
  const config = await loadConfig();

  return db.runTransaction(async (tx) => {
    const billRef = db.doc(`bills/${billId}`);
    const [billSnap, donorSnap, paySnap] = await Promise.all([
      tx.get(billRef), tx.get(db.doc(`donors/${uid}`)), tx.get(db.doc(`payments/${paymentId}`)),
    ]);
    if (!billSnap.exists) throw new HttpsError('not-found', 'Bill not found');
    const bill = billSnap.data();
    if (bill.userId === uid) throw new HttpsError('failed-precondition', 'Cannot fund your own bill');
    if (!paySnap.exists || paySnap.data().status !== 'captured' || paySnap.data().uid !== uid
        || paySnap.data().amount !== amt || paySnap.data().consumed) {
      throw new HttpsError('failed-precondition', 'Payment not verified');
    }
    const cat = (await tx.get(db.doc(`categories/${bill.subcategoryId || bill.categoryId}`))).data();
    const check = rules.donorCanFund(bill, cat, donorSnap.exists ? donorSnap.data() : {}, config);
    if (!check.allowed) throw new HttpsError('failed-precondition', check.reason);
    const applied = Math.min(amt, bill.remainingAmount);
    const remaining = bill.remainingAmount - applied;
    tx.update(billRef, {
      fundedAmount: FieldValue.increment(applied),
      remainingAmount: remaining,
      fundingStatus: remaining <= 0 ? 'funded' : 'partially_funded',
    });
    tx.update(paySnap.ref, { consumed: true, billId });
    tx.set(db.collection('donations').doc(), {
      billId, donorId: uid, amount: applied, currency: bill.currency, categoryId: bill.categoryId,
      createdAt: FieldValue.serverTimestamp(),
    });
    return { applied, remainingAmount: remaining };
  });
});

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
