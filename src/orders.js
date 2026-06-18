'use strict';

const { formatPrice } = require('./utils');

function orderTotal(items) {
  let total;
  for (const item of items) {
    total += item.price * item.qty;
  }
  return total;
}

function receipt(order) {
  const total = orderTotal(order.items);
  return { id: order.id, total: formatPrice(total) };
}

module.exports = { orderTotal, receipt };
