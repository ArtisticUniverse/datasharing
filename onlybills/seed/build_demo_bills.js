// Generates assets/demo/bills.json. Statuses come from the real server rules so
// demo mode shows exactly what production would decide for each bill.
const fs = require('fs');
const path = require('path');
const rules = require('../functions/rules');
const { build } = require('./build_seed');

const cats = Object.fromEntries(build().map((c) => [c.categoryId, c]));

// [merchant, subcategoryId, amount, alreadyFunded, city, urgency, purpose]
const SAMPLES = [
  ['Apollo Hospitals, Chennai', 'healthcare.surgery_and_operations', 85000, 32000, 'Chennai', 'critical', 'Appendix surgery for my 9-year-old daughter. Insurance covered part of the bill.'],
  ['MedPlus Pharmacy', 'healthcare.medicines_and_pharmacy', 2400, 600, 'Hyderabad', 'high', 'Monthly insulin and test strips for my father.'],
  ['City Diagnostics Lab', 'healthcare.x_rays_mri_ct_scans', 6500, 0, 'Pune', 'high', 'MRI prescribed after a back injury at work.'],
  ['Sunrise Public School', 'education.school_fees', 18000, 9000, 'Lucknow', 'medium', 'Term fees for two children, Class 4 and Class 7.'],
  ['Gyan Coaching Institute', 'education.competitive_exam_preparation', 12000, 0, 'Patna', 'medium', 'NEET preparation course fees.'],
  ['Bharat Book Depot', 'education.books_and_notebooks', 1800, 0, 'Jaipur', 'low', 'Textbooks for Class 10 board exams.'],
  ['BESCOM', 'housing.electricity_bills', 3200, 1000, 'Bengaluru', 'high', 'Two months of pending electricity bill; disconnection notice received.'],
  ['Delhi Jal Board', 'housing.water_bills', 950, 0, 'Delhi', 'medium', 'Quarterly water bill.'],
  ['DMart', 'food.groceries_and_supermarkets', 3500, 500, 'Mumbai', 'high', 'Monthly groceries for a family of five after a job loss.'],
  ['Annapurna Community Kitchen', 'food.community_kitchens', 15000, 4000, 'Kolkata', 'medium', 'Weekly meals for 120 people at a community kitchen.'],
  ['IRCTC', 'transport.medical_transport', 2100, 0, 'Bhopal', 'high', 'Train tickets to AIIMS Delhi for cancer follow-up.'],
  ['Jio', 'technology.data_packs', 299, 0, 'Indore', 'low', 'Data pack for online classes.'],
  ['Paws Veterinary Clinic', 'pets.veterinary_bills', 4200, 1200, 'Goa', 'medium', 'Treatment for a rescued street dog hit by a car.'],
  ['Kisan Agro Centre', 'livelihood.seeds_and_fertilizers', 9000, 3000, 'Nashik', 'high', 'Seeds and fertilizer for kharif sowing.'],
  ['Surat Municipal Corporation', 'government.birth_and_death_certificates', 150, 0, 'Surat', 'low', 'Certificate fees for school admission.'],
  ['Shanti Funeral Services', 'family.funeral_and_bereavement_expenses', 14000, 6000, 'Varanasi', 'critical', 'Funeral expenses for my mother.'],
  ['Helping Hands NGO', 'charity.disaster_relief', 50000, 21000, 'Guwahati', 'critical', 'Flood relief kits: rice, dal, tarpaulin and water purifiers.'],
  ['Spice Route Restaurant', 'food.restaurants', 1600, 0, 'Bengaluru', 'low', 'Dinner bill. Discretionary: shown only to donors who opt in.'],
  ['FitZone Gym', 'recreation.gym_membership', 3000, 0, 'Noida', 'low', 'Quarterly gym membership. Discretionary.'],
  ['HDFC Bank', 'finance_legal.credit_card_bills', 22000, 0, 'Mumbai', 'medium', 'Credit card dues. Consumer debt: waiting for moderator review.'],
  ['City Wine & Liquor Store', 'restricted_recreational.beer', 900, 0, 'Delhi', 'low', 'Restricted category example: never fundable by default.'],
  ['Tanishq', 'retail.jewellery', 45000, 0, 'Chennai', 'low', 'Luxury purchase example: restricted from funding.'],
];

// Moderator approval is simulated for 'review' categories except the debt example.
const AWAITING_REVIEW = new Set(['finance_legal.credit_card_bills']);

const bills = SAMPLES.map(([merchantName, cid, amount, funded, city, urgency, fundingPurpose], i) => {
  const c = cats[cid];
  if (!c) throw new Error(`Unknown category ${cid}`);
  const b = {
    billId: `demo_${i + 1}`, userId: `demo_user_${i % 7}`, merchantName,
    categoryId: c.parentCategoryId, subcategoryId: cid, amount, currency: 'INR',
    billDate: new Date(Date.UTC(2026, 9, 1 + (i % 25))).toISOString(), receiptImageUrl: '',
    fundedAmount: funded, remainingAmount: amount - funded,
    fundingStatus: funded ? 'partially_funded' : 'open', fundingPurpose, city, urgency,
    createdAt: new Date(Date.UTC(2026, 9, 26 - (i % 20), 10)).toISOString(),
  };
  const v = rules.verifyReceipt(b, c);
  const approved = !AWAITING_REVIEW.has(cid);
  b.reviewApproved = approved;
  b.verificationFlags = v.flags;
  b.verificationStatus = v.verificationStatus === 'rejected' ? 'rejected'
    : (approved && v.flags.length === 0 ? 'verified' : 'pending_review');
  const e = rules.billEligibility(b, c);
  b.fundingEligibility = e.fundingEligibility;
  b.eligibilityReasons = e.reasons;
  return b;
});

fs.writeFileSync(path.join(__dirname, '..', 'assets', 'demo', 'bills.json'), JSON.stringify(bills, null, 2));
for (const b of bills) console.log(b.subcategoryId.padEnd(45), b.verificationStatus.padEnd(15), b.fundingEligibility, b.verificationFlags.join(','));
