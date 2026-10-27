// Pure, dependency-free policy logic. Shared by Cloud Functions and unit tests,
// so every eligibility and fraud decision is made server-side, never trusted from the app.

const DEFAULT_CONFIG = {
  // Off by default: alcohol, tobacco, nicotine, vaping and other restricted products
  // are never charitably funded unless an admin explicitly enables them.
  restrictedFundingEnabled: false,
  // Regions where restricted categories may be funded at all (e.g. legal cannabis).
  restrictedAllowedRegions: [],
  // Classifications the payment provider refuses outright.
  paymentProviderBlockedClassifications: ['restricted', 'tax'],
  minimumDonorAge: 21,
  maxBillAmount: { INR: 500000, USD: 10000 },
  // Per-classification ceiling above which a bill is flagged as a suspicious total.
  suspiciousAmount: { essential: 200000, discretionary: 20000, luxury: 10000, restricted: 5000, debt: 200000, tax: 200000 },
};

// Merchant keywords used both for suggesting a category and for mismatch detection.
// Whole-word matches; order matters for ties (pets before healthcare: 'veterinary clinic').
const MERCHANT_KEYWORDS = {
  pets: ['veterinary', 'vet', 'pet', 'pets', 'animal'],
  healthcare: ['hospital', 'hospitals', 'clinic', 'pharmacy', 'medical', 'diagnostic', 'diagnostics', 'pathology', 'apollo', 'medplus', 'dental', 'nursing', 'lab', 'labs', 'chemist'],
  food: ['restaurant', 'cafe', 'kitchen', 'dhaba', 'swiggy', 'zomato', 'bakery', 'dmart', 'grocery', 'grocers', 'supermarket', 'bigbasket', 'foods', 'sweets'],
  restricted_recreational: ['wine', 'wines', 'liquor', 'beer', 'bar', 'pub', 'spirits', 'tobacco', 'vape', 'hookah', 'cigar', 'cigars', 'paan'],
  education: ['school', 'college', 'university', 'academy', 'coaching', 'institute', 'tuition', 'books', 'book', 'stationery'],
  housing: ['electricity', 'power', 'water board', 'jal board', 'gas', 'bescom', 'rent', 'plumbing', 'plumber', 'pest'],
  transport: ['railway', 'railways', 'irctc', 'metro', 'uber', 'ola', 'petrol', 'fuel', 'bus', 'redbus', 'motors', 'garage'],
  technology: ['jio', 'airtel', 'vodafone', 'vi', 'bsnl', 'broadband', 'recharge', 'mobile'],
  government: ['municipal', 'corporation', 'passport', 'government', 'nagar', 'registrar'],
};

function suggestCategory(merchantName = '', text = '') {
  const hay = `${merchantName} ${text}`.toLowerCase();
  let best = null;
  let bestScore = 0;
  for (const [cat, words] of Object.entries(MERCHANT_KEYWORDS)) {
    const score = words.filter((w) => new RegExp(`\\b${w}\\b`).test(hay)).length;
    if (score > bestScore) { best = cat; bestScore = score; }
  }
  return { categoryId: best || 'other', confidence: best ? Math.min(0.5 + 0.15 * bestScore, 0.95) : 0.1 };
}

function rootOf(categoryId) { return String(categoryId || '').split('.')[0]; }

// Returns { flags: [...], verificationStatus } for an uploaded bill.
function verifyReceipt(bill, category, { duplicateFound = false, config = DEFAULT_CONFIG } = {}) {
  const flags = [];
  if (duplicateFound) flags.push('duplicate_receipt');

  const ceiling = config.suspiciousAmount[category.classification];
  if (ceiling && bill.amount > ceiling) flags.push('suspicious_total');
  if (bill.ocr && typeof bill.ocr.extractedTotal === 'number'
      && Math.abs(bill.ocr.extractedTotal - bill.amount) > Math.max(1, bill.amount * 0.02)) {
    flags.push('amount_mismatch_with_receipt');
  }
  if (bill.ocr && Array.isArray(bill.ocr.lineItemTotals) && bill.ocr.lineItemTotals.length) {
    const sum = bill.ocr.lineItemTotals.reduce((a, b) => a + b, 0);
    if (Math.abs(sum - bill.amount) > Math.max(1, bill.amount * 0.05)) flags.push('line_items_do_not_add_up');
  }

  const sw = String((bill.imageMetadata && bill.imageMetadata.software) || '').toLowerCase();
  if (/photoshop|gimp|picsart|snapseed|canva|lightroom/.test(sw)) flags.push('possible_edited_image');

  const billDate = bill.billDate ? new Date(bill.billDate) : null;
  if (billDate && billDate.getTime() > Date.now() + 86400000) flags.push('future_dated');

  const suggested = suggestCategory(bill.merchantName, bill.ocr && bill.ocr.rawText);
  if (suggested.categoryId !== 'other' && suggested.categoryId !== rootOf(bill.categoryId)) {
    flags.push('merchant_category_mismatch');
  }
  // Someone filing a liquor-store receipt as groceries is the case we most need to catch.
  if (suggested.categoryId === 'restricted_recreational' && rootOf(bill.categoryId) !== 'restricted_recreational') {
    flags.push('possible_restricted_item_miscategorised');
  }

  let verificationStatus = 'verified';
  if (flags.includes('duplicate_receipt')) verificationStatus = 'rejected';
  else if (flags.length || category.requiresManualReview) verificationStatus = 'pending_review';
  return { flags, verificationStatus };
}

// Bill-level eligibility shown on the card: eligible | review | restricted.
function billEligibility(bill, category, config = DEFAULT_CONFIG) {
  const reasons = [];
  if (!category || !category.isActive) return { fundingEligibility: 'restricted', reasons: ['category_inactive'] };

  if (category.fundingEligibility === 'restricted') {
    const regionOk = config.restrictedAllowedRegions.includes(bill.region);
    const providerOk = !config.paymentProviderBlockedClassifications.includes(category.classification);
    if (category.classification === 'luxury') {
      reasons.push('luxury_purchase');
    } else {
      if (!config.restrictedFundingEnabled) reasons.push('restricted_by_platform_policy');
      if (!providerOk) reasons.push('blocked_by_payment_provider');
      if (category.legalJurisdictionsOnly && !regionOk) reasons.push('not_legal_in_region');
    }
    if (reasons.length) return { fundingEligibility: 'restricted', reasons };
  }
  if (bill.verificationStatus === 'rejected') return { fundingEligibility: 'restricted', reasons: ['verification_rejected'] };
  if (bill.verificationStatus !== 'verified') reasons.push('awaiting_verification');
  if (category.fundingEligibility === 'review' && !bill.reviewApproved) reasons.push('awaiting_moderator_review');
  return { fundingEligibility: reasons.length ? 'review' : 'eligible', reasons };
}

// Whether this donor may fund this bill right now. Used by the fund callable.
function donorCanFund(bill, category, donor, config = DEFAULT_CONFIG) {
  const elig = billEligibility(bill, category, config);
  if (elig.fundingEligibility !== 'eligible') return { allowed: false, reason: elig.reasons[0] };
  const prefs = donor.preferences || {};
  const root = rootOf(category.categoryId);
  if ((prefs.excludedCategoryIds || []).some((id) => id === category.categoryId || id === root)) {
    return { allowed: false, reason: 'excluded_by_donor' };
  }
  if (category.requiresAgeVerification) {
    if (!donor.ageVerified || (donor.age || 0) < config.minimumDonorAge) return { allowed: false, reason: 'age_verification_required' };
    if (!prefs.allowRestrictedCategories) return { allowed: false, reason: 'donor_has_not_opted_in' };
  }
  if (bill.remainingAmount <= 0) return { allowed: false, reason: 'fully_funded' };
  return { allowed: true };
}

// Default donor feed hides everything except essentials unless the donor opts in.
function visibleInFeed(bill, category, prefs = {}) {
  const root = rootOf(category.categoryId);
  const excluded = prefs.excludedCategoryIds || [];
  if (excluded.includes(root) || excluded.includes(category.categoryId)) return false;
  const included = prefs.includedCategoryIds || [];
  if (included.length && !included.includes(root) && !included.includes(category.categoryId)) return false;
  if (category.classification === 'restricted' && !prefs.allowRestrictedCategories) return false;
  if (['discretionary', 'luxury'].includes(category.classification) && !prefs.showDiscretionary) return false;
  if (['debt', 'tax'].includes(category.classification) && !prefs.showDebtAndTax) return false;
  return true;
}

// Strips identifiers from OCR text before anything is stored or shown to donors.
const REDACTIONS = [
  [/\b\d{4}\s?\d{4}\s?\d{4}\b/g, '[AADHAAR]'],
  [/\b[A-Z]{5}\d{4}[A-Z]\b/g, '[PAN]'],
  [/\b(?:\d[ -]?){13,19}\b/g, '[CARD/ACCOUNT]'],
  [/\b(?:\+91[\s-]?)?[6-9]\d{9}\b/g, '[PHONE]'],
  [/[\w.+-]+@[\w-]+\.[\w.]+/g, '[EMAIL]'],
  [/\b(?:UHID|MRN|IP\s?No|Patient\s?ID|Reg\.?\s?No)[:#.\s]*[\w/-]+/gi, '[PATIENT-ID]'],
  [/\b(?:A\/?C|Account)\s*(?:No\.?)?[:#\s]*\d+/gi, '[ACCOUNT]'],
  [/\b\d{6}\b(?=\s*$|\s*[,\n])/gm, '[PIN]'],
];
function redact(text = '') {
  return REDACTIONS.reduce((t, [re, rep]) => t.replace(re, rep), text);
}

module.exports = {
  DEFAULT_CONFIG, MERCHANT_KEYWORDS, suggestCategory, verifyReceipt, billEligibility, donorCanFund, visibleInFeed, redact, rootOf,
};
