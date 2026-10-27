// Single source of truth for the OnlyBills category tree.
// `npm run build:seed` (in functions/) turns this into:
//   seed/categories.json          -> uploaded to Firestore by seed/seed_firestore.js
//   assets/demo/categories.json   -> bundled for the app's demo/offline mode
//
// classification: essential | discretionary | luxury | restricted | debt | tax
// fundingEligibility: eligible | review | restricted
//   eligible   - may appear in donor feeds once the bill is verified
//   review     - a moderator must approve each bill before it is fundable
//   restricted - never charitably fundable unless platform config + donor + law allow it

const E = { classification: 'essential', fundingEligibility: 'eligible' };
const ER = { classification: 'essential', fundingEligibility: 'review', requiresManualReview: true };
const D = { classification: 'discretionary', fundingEligibility: 'review', requiresManualReview: true };
const L = { classification: 'luxury', fundingEligibility: 'restricted' };
const R = { classification: 'restricted', fundingEligibility: 'restricted', requiresAgeVerification: true, requiresManualReview: true };
const DEBT = { classification: 'debt', fundingEligibility: 'review', requiresManualReview: true };
const TAX = { classification: 'tax', fundingEligibility: 'restricted', requiresManualReview: true };

// [id, name, icon, defaults, description, subcategories]
// subcategory: 'Name' or ['Name', overrides]
module.exports = [
  ['healthcare', 'Healthcare & Medical', 'local_hospital', E, 'Medical treatment, medicines and care.', [
    'Hospital Bills', 'Emergency Treatment', 'Surgery & Operations', 'Doctor Consultation',
    'Diagnostic Tests & Pathology', 'X-rays, MRI, CT Scans', 'Medicines & Pharmacy', 'Dental Treatment',
    'Eye Care & Spectacles', 'Pregnancy & Maternity Care', 'Child Healthcare', 'Ambulance Services',
    'Physiotherapy & Rehabilitation', 'Mental Healthcare', 'Medical Equipment', 'Disability Support',
    'Veterinary & Pet Healthcare', ['Health Insurance Premiums', ER]]],
  ['food', 'Food, Dining & Restaurants', 'restaurant', E, 'Groceries, meals and food assistance.', [
    ['Restaurants', D], ['Cafes & Coffee Shops', D], ['Street Food', D], ['Fast Food', D], ['Fine Dining', L],
    ['Food Delivery', D], ['Takeaway Orders', D], ['Bakery & Desserts', D], ['Ice Cream & Frozen Desserts', D],
    ['Pizza & Burgers', D], 'Indian Meals & Thalis', 'Groceries & Supermarkets', 'Fruits & Vegetables',
    'Dairy Products', 'Meat & Seafood', 'Tiffin & Meal Services', 'School & College Canteens', ['Office Meals', D],
    'Community Kitchens', 'Food for Families in Need']],
  ['restricted_recreational', 'Alcohol, Tobacco & Recreational Products', 'no_drinks', R,
    'Age-restricted products. Excluded from charitable funding by default.', [
    'Alcoholic Beverages', 'Beer', 'Wine', 'Spirits', 'Cigarettes', 'Cigars', 'Tobacco Products',
    'Vapes & E-cigarettes', 'Hookah & Shisha', 'Nicotine Products',
    ['Cannabis Products (where legally permitted)', { legalJurisdictionsOnly: true }]]],
  ['beverages', 'Beverages & Refreshments', 'local_drink', D, 'Non-alcoholic drinks.', [
    ['Bottled Water', E], 'Soft Drinks', 'Juices', 'Tea', 'Coffee', 'Energy Drinks', 'Sports Drinks',
    ['Milk & Milkshakes', E], 'Smoothies', 'Non-alcoholic Mocktails', 'Packaged Beverages']],
  ['education', 'Education & Learning', 'school', E, 'Fees, supplies and learning tools.', [
    'School Fees', 'College Fees', 'University Tuition', 'Examination Fees', 'Coaching Classes',
    'Competitive Exam Preparation', 'Books & Notebooks', 'School Uniforms', 'Stationery',
    'Laptops & Tablets for Education', 'Internet for Online Learning', 'Online Courses', 'Vocational Training',
    'Skill Development', ['Educational Travel', ER], 'Special Education', ['Scholarships', ER]]],
  ['housing', 'Housing & Household Expenses', 'home', E, 'Rent, utilities and essential home costs.', [
    'House Rent', ['Security Deposit', ER], 'Electricity Bills', 'Water Bills', 'Gas Bills', 'Internet Bills',
    'Mobile Bills', 'Home Repairs', 'Plumbing', 'Electrical Repairs', 'Essential Appliances', ['Furniture', ER],
    'Bedding & Mattresses', 'Kitchen Essentials', 'Cleaning Supplies', 'Pest Control', 'Household Maintenance',
    'Temporary Shelter', 'Homelessness Support']],
  ['transport', 'Transportation & Travel', 'directions_bus', E, 'Getting to school, work and care.', [
    'Bus Tickets', 'Train Tickets', 'Metro Tickets', ['Taxi & Cab Fares', ER], 'Auto-Rickshaw Fares', 'Fuel',
    'Electric Vehicle Charging', 'Vehicle Repairs', ['Vehicle Insurance', ER], 'Bicycle Repairs', 'School Transport',
    'Medical Transport', ['Flight Tickets', D], ['Hotel Stays', D], ['Emergency Travel', ER],
    'Public Transport Passes', 'Toll & Parking Fees']],
  ['family', 'Family & Personal Needs', 'family_restroom', E, 'Everyday needs for families and individuals.', [
    'Baby Products', 'Diapers & Infant Care', 'Childcare', 'Elderly Care', 'Clothing', 'Footwear', 'Winter Wear',
    'Hygiene Products', 'Sanitary Products', 'Personal Care', 'Laundry', ['Haircuts & Grooming', D],
    'Essential Household Supplies', ['Family Emergency Expenses', ER], 'Funeral & Bereavement Expenses',
    ['Marriage-Related Essential Expenses', ER]]],
  ['livelihood', 'Employment & Livelihood', 'work', E, 'Costs of finding work and earning a living.', [
    'Job Application Fees', 'Professional Certification', 'Work Uniforms', 'Safety Equipment', 'Work Tools',
    'Professional Software', 'Internet for Remote Work', 'Work-Related Travel', 'Business Registration Fees',
    'Small Business Supplies', 'Vendor & Artisan Expenses', 'Agricultural Inputs', 'Seeds & Fertilizers',
    'Farming Equipment', 'Livestock Care', 'Market Stall Fees']],
  ['finance_legal', 'Finance, Insurance & Legal', 'account_balance', ER,
    'Insurance, legal help and fees. Debt and taxes are classified separately and reviewed.', [
    ['Bank Charges', DEBT], ['Loan Repayment', DEBT], ['Credit Card Bills', DEBT], 'Insurance Premiums',
    'Life Insurance', 'Health Insurance', 'Vehicle Insurance', ['Legal Consultation', E],
    ['Document Preparation', E], ['Government Application Fees', E], 'Passport & Visa Fees',
    ['Tax Payments', TAX], 'Court-Related Expenses', ['Financial Counselling', E]]],
  ['technology', 'Technology & Communications', 'smartphone', E, 'Staying connected.', [
    'Mobile Recharge', 'Postpaid Mobile Bills', 'Broadband & Wi-Fi', 'Laptop Repairs', 'Phone Repairs',
    ['Computer Accessories', ER], ['Software Subscriptions', D], ['Cloud Storage', D], 'Assistive Technology',
    'Digital Learning Tools', 'Data Packs']],
  ['recreation', 'Fitness, Sports & Recreation', 'sports_soccer', D,
    'Discretionary entertainment and activities, kept separate from essentials.', [
    'Gym Membership', 'Sports Equipment', 'Sports Club Fees', 'Swimming Classes', 'Yoga Classes', 'Dance Classes',
    'Music Lessons', 'Art Classes', "Children's Activities", 'Recreational Tickets', ['Gaming Purchases', L],
    ['Streaming Subscriptions', L], 'Hobbies & Crafts']],
  ['events', 'Events, Hospitality & Celebrations', 'celebration', D, 'Celebrations and gatherings.', [
    'Birthday Celebrations', 'Weddings', 'Catering', ['Banquet Hall Bills', L], ['Event Venue Rentals', L],
    'Decorations', ['Photography', L], ['Community Events', ER], ['Religious & Cultural Events', ER],
    'Festival Supplies', 'Travel for Family Events']],
  ['charity', 'Charity, Community & Social Welfare', 'volunteer_activism', ER,
    'Community programmes. Organisations are verified before funding.', [
    'NGO Expenses', 'Orphanage Supplies', 'Old-Age Home Supplies', 'Disability Support', 'Disaster Relief',
    'Food Distribution', 'Clothing Donations', 'Animal Rescue', 'Community Healthcare', 'Community Education',
    'Clean Water Projects', 'Sanitation Projects', 'Shelter & Rehabilitation', 'Rural Development',
    'Environmental Projects']],
  ['government', 'Government & Essential Services', 'gavel', E, 'Public service fees and arrears.', [
    'Utility Arrears', 'Municipal Bills', 'Public Service Fees', 'Birth & Death Certificates',
    'Identity Document Fees', 'Permits & Licences', 'Essential Government Charges', 'Emergency Relief Fees']],
  ['pets', 'Pets & Animal Welfare', 'pets', E, 'Care for pets, livestock and rescued animals.', [
    'Pet Food', 'Veterinary Bills', 'Vaccinations', 'Pet Medicines', ['Pet Grooming', D], 'Animal Rescue',
    'Animal Shelter Expenses', 'Livestock Treatment', 'Animal Shelter Supplies']],
  ['tourism', 'Tourism & Accommodation', 'hotel', D, 'Stays and travel. Emergency and student housing are essential.', [
    'Hotel Bills', 'Hostel Fees', 'Guesthouse Bills', 'Homestays', ['Emergency Accommodation', E],
    ['Student Hostel Fees', E], 'Travel Bookings', ['Tour Packages', L], ['Local Experiences', L]]],
  ['retail', 'Shopping & Retail', 'shopping_bag', D,
    'Retail purchases. Luxury items are excluded from essential recommendations.', [
    'Clothing Stores', 'Footwear Stores', 'Electronics', 'Home Goods', 'Department Stores', 'Online Shopping',
    ['Gifts', L], ['Jewellery', L], ['Luxury Goods', L], 'Accessories']],
  ['other', 'Other & Custom Categories', 'more_horiz', { ...ER }, 'Anything else. Always reviewed.', [
    'Miscellaneous Bills', 'Other Essential Expenses', ['Other Non-Essential Expenses', D],
    'Custom User Category', 'Unclassified Receipt']],
];
