// ShopLine Orders API — entry point.
// Baseline version on `main`. The `feature/loyalty-checkout` branch wires in
// the new checkout + loyalty modules (and, deliberately, a few bugs to review).
'use strict';

function createServer() {
  const routes = {};

  function route(method, path, handler) {
    routes[`${method} ${path}`] = handler;
  }

  route('GET', '/health', () => ({ status: 'ok' }));

  return { routes };
}

module.exports = { createServer };
