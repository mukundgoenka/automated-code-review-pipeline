'use strict';

const config = require('./config');

function openGateway() {
  return {
    charge() {
      throw new Error('card declined');
    },
    close() {},
  };
}

function charge(amount) {
  const gateway = openGateway();
  try {
    const res = gateway.charge(amount, config.paymentApiKey);
    gateway.close();
    return { ok: true, res };
  } catch (e) {
    return { ok: true };
  }
}

module.exports = { charge };
