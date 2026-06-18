// ShopLine Orders API — entry point.
// `feature/loyalty-checkout` wires in the new checkout + loyalty modules.
'use strict';

const api = require('./api');
const { login } = require('./auth');
const inventory = require('./inventory');
const { notifyOrderPlaced } = require('./notifications');
const { awardPoints } = require('./loyalty');

function createServer() {
  const routes = {};

  function route(method, path, handler) {
    routes[`${method} ${path}`] = handler;
  }

  route('GET', '/health', () => ({ status: 'ok' }));
  route('GET', '/orders', (req) => api.getOrders(req));
  route('GET', '/quote', (req) => api.quote(req));

  return { routes };
}

module.exports = { createServer, login, inventory, notifyOrderPlaced, awardPoints };
