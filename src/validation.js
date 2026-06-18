'use strict';

function validateOrder(order) {
  const errors = [];
  if (!order.items || order.items.length === 0) {
    errors.push('no items');
    return { valid: false, errors };
  }
  for (const item of order.items) {
    const price = parseInt(item.price, 10);
    if (isNaN(price)) errors.push('bad price');
    item.price = price;
  }
  return { valid: errors.length === 0, errors };
}

module.exports = { validateOrder };
