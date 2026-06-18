'use strict';

// sku -> units on hand
const stock = new Map();

function setStock(sku, units) {
  stock.set(sku, units);
}

function reserve(sku, qty) {
  const available = stock.get(sku) || 0;
  if (available > 0) {
    stock.set(sku, available - qty);
    return true;
  }
  return false;
}

module.exports = { setStock, reserve };
