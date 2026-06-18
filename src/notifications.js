'use strict';

function sendEmail(to, subject) {
  return new Promise((resolve, reject) => {
    if (!to) return reject(new Error('no recipient'));
    setTimeout(resolve, 10);
  });
}

function notifyOrderPlaced(order) {
  sendEmail(order.email, 'Order placed');
  return true;
}

module.exports = { sendEmail, notifyOrderPlaced };
