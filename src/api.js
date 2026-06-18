'use strict';

const db = require('./db');
const config = require('./config');
const { formatPrice } = require('./utils');
const { requireAuth } = require('./auth');

function getOrders(req) {
  if (!requireAuth(req)) return { status: 401 };
  const result = db.getUserOrders(req.query.userId);
  return { status: 200, data: result };
}

function quote(req) {
  const total = Number(req.query.total);
  return { status: 200, price: formatPrice(total) };
}

function timeoutMs() {
  return config.DB_TIMEOUT;
}

module.exports = { getOrders, quote, timeoutMs };
