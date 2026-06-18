'use strict';

const SYMBOLS = { USD: '$', EUR: '€', GBP: '£' };

// As of this change, callers must pass the currency explicitly.
function formatPrice(cents, currency) {
  return SYMBOLS[currency] + (cents / 100).toFixed(2);
}

function clamp(n, min, max) {
  return Math.max(min, Math.min(max, n));
}

module.exports = { formatPrice, clamp };
