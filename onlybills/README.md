# OnlyBills

People upload bills and receipts. Donors swipe right to fund eligible bills and left to skip them.
This folder holds the **category and classification system**: a Flutter (Android) app, a Firebase
backend that makes every decision, and a demo mode with sample bills.

## Layout

```
seed/taxonomy.js            The single source for all 19 main categories and 250 subcategories
seed/build_seed.js          Builds categories.json (for Firestore + demo asset) from the taxonomy
seed/build_demo_bills.js    Builds the 22 demo bills; their statuses come from the real server rules
seed/seed_firestore.js      Uploads categories + default funding config to Firestore
functions/rules.js          Pure policy logic: eligibility, donor checks, receipt verification, redaction
functions/payments.js       Payment data pipeline + per-donor method/amount recommendations
functions/index.js          Cloud Functions: submitBill, getCheckout, createPaymentOrder, razorpayWebhook, reviewBill, upsert/reorder/mergeCategories, analytics
functions/test/             Node tests for the policy (`npm test`)
firestore.rules, storage.rules, firestore.indexes.json
lib/                        Flutter app (models, data layer, screens, widgets)
assets/demo/                Generated categories.json + bills.json for demo mode
```

## Category model

Categories live in Firestore (`categories/{categoryId}`), not in the app. Main categories have
`parentCategoryId: null`; subcategories use ids like `healthcare.x_rays_mri_ct_scans`. An optional
third level (specific bill type) is a category whose parent is a subcategory, stored on the bill as `billTypeId`.

Fields: `categoryId, categoryName, localizedNames {en, hi, …}, parentCategoryId, description, icon,
isActive, requiresAgeVerification, requiresManualReview, fundingEligibility, classification,
legalJurisdictionsOnly, displayOrder`.

Two fields drive the policy:

| `classification` | Meaning | Default donor feed |
|---|---|---|
| `essential` | Medical, education, utilities, groceries, … | shown |
| `discretionary` | Restaurants, gym, events, general retail | hidden unless the donor opts in |
| `luxury` | Jewellery, fine dining, streaming, gaming | restricted |
| `restricted` | Alcohol, tobacco, nicotine, vaping, cannabis | restricted, 18+/21+ |
| `debt` | Credit cards, loans, bank charges | hidden unless opted in, moderator review |
| `tax` | Tax payments | restricted |

`fundingEligibility` is `eligible`, `review` (a moderator approves each bill) or `restricted`.
Each bill gets its own eligibility (shown on the card as **Eligible / Awaiting review / Restricted**)
from its category, its verification result and the platform config.

### Restricted products

Alcohol, tobacco, nicotine, vaping and cannabis are a separate main category with
`requiresAgeVerification: true`. They are **never fundable by default**. Funding one needs all of:

1. An admin sets `config/funding.restrictedFundingEnabled = true`.
2. The payment provider allows it (`paymentProviderBlockedClassifications` doesn't list `restricted`).
3. Cannabis only: the bill's region is in `restrictedAllowedRegions`.
4. The donor is age-verified on the server (`donors/{uid}.ageVerified`, which clients cannot write) and at least `minimumDonorAge`.
5. The donor has opted in (`allowRestrictedCategories`).

The receipt checks also flag a liquor or tobacco merchant filed under another category (`possible_restricted_item_miscategorised`).

## Receipt verification (server-side, in `submitBill`)

- **Duplicates**: SHA-256 of the image, plus a merchant/amount/date fingerprint → rejected.
- **Suspicious totals**: per-classification ceilings; the entered amount is compared with the OCR total and the sum of line items.
- **Edited images**: EXIF `Software` tag from an editor (Photoshop, PicsArt, Snapseed, …). This is a weak signal, because stripping EXIF defeats it. Plug in an image-forensics service for real detection.
- **Merchant vs category mismatch**: whole-word merchant keyword matching.
- Any flag, or a category with `requiresManualReview`, sends the bill to `pending_review`.

## Privacy

OCR runs on the device (ML Kit). Before upload, the text is redacted for Aadhaar, PAN, card and account
numbers, phone numbers, emails, patient IDs/UHID/MRN and PIN codes. The server redacts again, so a
modified client can't skip it. Original receipts are readable only by the uploader and admins (`storage.rules`).
Donors see category, merchant, city, amount, purpose, verification status and amount remaining.
The `redacted/` storage path is reserved for a server-generated redacted image (not implemented yet).

## Running

```bash
# 1. Generate platform folders (only android/ is needed)
flutter create --platforms=android --project-name onlybills .
# set minSdkVersion 23 in android/app/build.gradle (Firebase + ML Kit)

# 2. Demo mode (default; no Firebase project needed)
flutter pub get
flutter run

# 3. Live mode
flutterfire configure            # adds google-services.json
cd functions && npm install && npm test && cd ..
firebase deploy --only firestore,storage,functions
GOOGLE_APPLICATION_CREDENTIALS=sa.json node seed/seed_firestore.js
flutter run --dart-define=DEMO=false
```

To edit categories in bulk, change `seed/taxonomy.js`, run `npm run build:seed` in `functions/`, and
re-seed. For one-off changes, use the in-app admin screen (Preferences → Manage categories). It needs the
`admin: true` custom claim, which you set with the Admin SDK.

Hindi and other languages: add `localizedNames.hi` (etc.) to category documents. The app falls back to English.

## Payments

Swiping right opens a one-tap pay sheet. The amount and payment method are already chosen for that donor,
and they can change either one.

```
getCheckout ──► pay sheet ──► createPaymentOrder ──► Razorpay checkout ──► razorpayWebhook (signed)
   ▲                                                                            │
   │                                                                     applyDonation (transaction,
   │                                                                     idempotent, refunds excess)
   │                                                                            │
donors/{uid}.paymentProfile ◄── onPaymentEvent ◄──────── paymentEvents/{id} ◄───┘
analytics/paymentMethods    ◄── nightlyPaymentStats (30-day window, marks abandoned checkouts)
```

- **Event log** (`paymentEvents`): one row per attempt state (created, captured, failed, abandoned). Rows can arrive twice or out of order; only the latest final state of each payment counts.
- **Donor profile** (rebuilt on every final event): usual amount (median, p75), success and failure per method and amount band, last method used, abandon rate. No card or bank details are stored.
- **Platform stats** (nightly): success rate per method × amount band (under ₹500, ₹500–2k, ₹2k–10k, ₹10k–50k, over ₹50k).
- **Ranking** (`recommendMethods`): expected success from the donor's own record, blended with platform data and then a prior when data is thin; a small boost for methods they've used; minus the fee, because fees reduce what reaches the bill. UPI is hidden above ₹1,00,000 and wallets above ₹10,000. Each option shows its reasons ("You used this last time · No fee · 94% success for amounts like this").
- **Amounts** (`suggestAmounts`): about half, equal to, and above the donor's usual gift, rounded to friendly numbers, plus "pay the rest". They never exceed what is left.
- If a payment fails, the sheet re-ranks with the failure counted and pre-selects the next best method.

Safety: the app never marks a payment paid. Only a webhook with a valid HMAC signature, matching order id and
exact amount settles it, inside a transaction that applies each payment once. If the bill filled up meanwhile,
the excess is recorded as `refundDue`. When a bill is fully funded, a `payouts/{billId}` record is queued for the
merchant or verified beneficiary.

`functions/payments.js` and `lib/services/payment_engine.dart` hold the same logic (server and demo mode) and
share test cases. `npm run test:emulator` runs the full settlement path against the Firestore emulator.

Setup: `firebase functions:secrets:set RAZORPAY_KEY_ID` (and `RAZORPAY_KEY_SECRET`, `RAZORPAY_WEBHOOK_SECRET`),
then point a Razorpay webhook for `payment.captured` and `payment.failed` at the `razorpayWebhook` URL.

## Not done yet

- **Refund and payout execution**: `refundDue` and `payouts/*` are recorded but not yet sent to Razorpay's Refunds / Route APIs.
- **Live payments on web**: `razorpay_flutter` is Android/iOS only; a web build needs Razorpay's checkout.js. Demo mode works on web.
- Age/KYC verification flow that sets `donors/{uid}.ageVerified`.
- Server-generated redacted receipt images; moderator review UI (the `reviewBill` function exists).
