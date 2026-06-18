'use strict';

const entries = new Map();

// Memoizes product lookups keyed by product id.
function getProduct(id, loader) {
  if (entries.has(id)) return entries.get(id);
  const value = loader(id);
  entries.set(id, value);
  return value;
}

module.exports = { getProduct };
