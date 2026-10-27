// Usage: GOOGLE_APPLICATION_CREDENTIALS=sa.json node seed/seed_firestore.js
// Idempotent: re-running updates category fields but never touches bills.
const admin = require('../functions/node_modules/firebase-admin');
const { build } = require('./build_seed');
const { DEFAULT_CONFIG } = require('../functions/rules');

admin.initializeApp();
const db = admin.firestore();

(async () => {
  const cats = build();
  for (let i = 0; i < cats.length; i += 400) {
    const batch = db.batch();
    cats.slice(i, i + 400).forEach((c) => batch.set(db.doc(`categories/${c.categoryId}`), c, { merge: true }));
    await batch.commit();
  }
  await db.doc('config/funding').set(DEFAULT_CONFIG, { merge: true });
  await db.doc('config/categoriesVersion').set({ version: admin.firestore.FieldValue.increment(1) }, { merge: true });
  console.log(`Seeded ${cats.length} categories`);
})();
