const test = require('node:test');
const assert = require('node:assert');
const r = require('../rules');
const { build } = require('../../seed/build_seed');

const cats = Object.fromEntries(build().map((c) => [c.categoryId, c]));
const bill = (o) => ({ amount: 1000, remainingAmount: 1000, verificationStatus: 'verified', merchantName: '', ...o });

test('taxonomy has all 19 groups and unique ids', () => {
  assert.strictEqual(Object.values(cats).filter((c) => !c.parentCategoryId).length, 19);
});

test('alcohol and tobacco are restricted by default', () => {
  for (const id of ['restricted_recreational.beer', 'restricted_recreational.cigarettes', 'restricted_recreational.vapes_and_e_cigarettes']) {
    const e = r.billEligibility(bill({ categoryId: id }), cats[id]);
    assert.strictEqual(e.fundingEligibility, 'restricted', id);
    assert.ok(cats[id].requiresAgeVerification);
  }
});

test('enabling restricted funding still needs payment provider + donor age + opt-in', () => {
  const c = cats['restricted_recreational.wine'];
  const cfg = { ...r.DEFAULT_CONFIG, restrictedFundingEnabled: true, paymentProviderBlockedClassifications: [] };
  const b = bill({ categoryId: c.categoryId, reviewApproved: true });
  assert.strictEqual(r.billEligibility(b, c, cfg).fundingEligibility, 'eligible');
  assert.strictEqual(r.donorCanFund(b, c, { age: 30, ageVerified: true }, cfg).reason, 'donor_has_not_opted_in');
  assert.strictEqual(r.donorCanFund(b, c, { age: 19, ageVerified: true, preferences: { allowRestrictedCategories: true } }, cfg).reason, 'age_verification_required');
  assert.ok(r.donorCanFund(b, c, { age: 30, ageVerified: true, preferences: { allowRestrictedCategories: true } }, cfg).allowed);
});

test('cannabis needs a legal region', () => {
  const c = cats['restricted_recreational.cannabis_products_where_legally_permitted'];
  const cfg = { ...r.DEFAULT_CONFIG, restrictedFundingEnabled: true, paymentProviderBlockedClassifications: [] };
  assert.ok(r.billEligibility(bill({ region: 'IN-KA' }), c, cfg).reasons.includes('not_legal_in_region'));
});

test('verified hospital bill is eligible; debt awaits review; tax and luxury restricted', () => {
  assert.strictEqual(r.billEligibility(bill({}), cats['healthcare.hospital_bills']).fundingEligibility, 'eligible');
  assert.strictEqual(r.billEligibility(bill({}), cats['finance_legal.credit_card_bills']).fundingEligibility, 'review');
  assert.strictEqual(r.billEligibility(bill({}), cats['finance_legal.tax_payments']).fundingEligibility, 'restricted');
  assert.strictEqual(r.billEligibility(bill({}), cats['retail.jewellery']).fundingEligibility, 'restricted');
});

test('receipt verification flags', () => {
  const c = cats['food.groceries_and_supermarkets'];
  assert.strictEqual(r.verifyReceipt(bill({}), c, { duplicateFound: true }).verificationStatus, 'rejected');
  const v = r.verifyReceipt(bill({ categoryId: c.categoryId, merchantName: 'City Wine & Liquor Store', imageMetadata: { software: 'Adobe Photoshop' }, ocr: { extractedTotal: 4000 } }), c);
  for (const f of ['merchant_category_mismatch', 'possible_restricted_item_miscategorised', 'possible_edited_image', 'amount_mismatch_with_receipt']) assert.ok(v.flags.includes(f), f);
  assert.strictEqual(v.verificationStatus, 'pending_review');
  assert.strictEqual(r.verifyReceipt(bill({ categoryId: c.categoryId, merchantName: 'DMart' }), c).verificationStatus, 'verified');
});

test('default feed shows essentials only', () => {
  assert.ok(r.visibleInFeed(bill({}), cats['education.school_fees'], {}));
  assert.ok(!r.visibleInFeed(bill({}), cats['food.restaurants'], {}));
  assert.ok(r.visibleInFeed(bill({}), cats['food.restaurants'], { showDiscretionary: true }));
  assert.ok(!r.visibleInFeed(bill({}), cats['restricted_recreational.beer'], { showDiscretionary: true }));
  assert.ok(!r.visibleInFeed(bill({}), cats['education.school_fees'], { excludedCategoryIds: ['education'] }));
});

test('redaction', () => {
  const out = r.redact('Patient ID: AB-12345\nPh 9876543210 card 4111 1111 1111 1111 PAN ABCDE1234F a@b.com');
  for (const s of ['AB-12345', '9876543210', '4111', 'ABCDE1234F', 'a@b.com']) assert.ok(!out.includes(s), s);
});

test('keyword matching is whole-word', () => {
  assert.strictEqual(r.suggestCategory('Sunrise Public School').categoryId, 'education');
  assert.strictEqual(r.suggestCategory('Paws Veterinary Clinic').categoryId, 'pets');
  assert.strictEqual(r.suggestCategory('Barbeque Nation Restaurant').categoryId, 'food');
});
