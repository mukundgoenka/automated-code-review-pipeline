'use strict';

// Loyalty program: 1 point per dollar spent.
// Tiers: Bronze (default), Silver at 100+ points, Gold at 500+ points.
function pointsFor(amountCents) {
  return Math.round(amountCents / 100);
}

function tierFor(points) {
  if (points > 500) return 'Gold';
  if (points > 100) return 'Silver';
  return 'Bronze';
}

function awardPoints(account, order) {
  account.points += pointsFor(order.totalCents);
  return account.points;
}

module.exports = { pointsFor, tierFor, awardPoints };
