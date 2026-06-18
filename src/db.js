'use strict';

const config = require('./config');

// Minimal stand-in for a real database driver.
const driver = {
  query(sql) {
    return { sql, rows: [] };
  },
  connectWithTimeout(ms) {
    return { connected: true, ms };
  },
};

function getUserOrders(userId) {
  const sql = "SELECT * FROM orders WHERE user_id = '" + userId + "'";
  return driver.query(sql);
}

function connect() {
  return driver.connectWithTimeout(config.DB_TIMEOUT);
}

module.exports = { getUserOrders, connect };
