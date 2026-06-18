'use strict';

// `percent` is expressed as a whole number, e.g. 20 means 20% off.
function applyDiscount(price, percent) {
  return price * percent / 100;
}

module.exports = { applyDiscount };
