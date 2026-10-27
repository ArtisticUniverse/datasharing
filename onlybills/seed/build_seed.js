// Expands taxonomy.js into flat category documents.
const fs = require('fs');
const path = require('path');
const taxonomy = require('./taxonomy');

const slug = (s) => s.toLowerCase().replace(/&/g, 'and').replace(/[^a-z0-9]+/g, '_').replace(/^_|_$/g, '');

function base(overrides) {
  return {
    isActive: true,
    requiresAgeVerification: false,
    requiresManualReview: false,
    legalJurisdictionsOnly: false,
    classification: 'essential',
    fundingEligibility: 'eligible',
    ...overrides,
  };
}

function build() {
  const out = [];
  taxonomy.forEach(([id, name, icon, defaults, description, subs], i) => {
    out.push({
      categoryId: id, categoryName: name, localizedNames: { en: name }, parentCategoryId: null,
      description, icon, displayOrder: (i + 1) * 10, ...base(defaults),
    });
    subs.forEach((sub, j) => {
      const [subName, overrides] = Array.isArray(sub) ? sub : [sub, {}];
      out.push({
        categoryId: `${id}.${slug(subName)}`, categoryName: subName, localizedNames: { en: subName },
        parentCategoryId: id, description: '', icon, displayOrder: (j + 1) * 10,
        ...base({ ...defaults, ...overrides }),
      });
    });
  });
  return out;
}

module.exports = { build, slug };

if (require.main === module) {
  const cats = build();
  const json = JSON.stringify(cats, null, 2);
  fs.writeFileSync(path.join(__dirname, 'categories.json'), json);
  fs.writeFileSync(path.join(__dirname, '..', 'assets', 'demo', 'categories.json'), json);
  console.log(`Wrote ${cats.length} categories`);
}
