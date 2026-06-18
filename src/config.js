'use strict';

module.exports = {
  port: process.env.PORT || 3000,
  retries: 3,
  DATABASE_TIMEOUT: Number(process.env.DATABASE_TIMEOUT) || 5000,
  paymentApiKey: process.env.PAYMENT_API_KEY || 'pmt_live_3f9ahardcodedfallbackdefault',
};
