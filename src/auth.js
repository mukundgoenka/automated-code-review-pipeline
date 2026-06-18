'use strict';

// In-memory session store: token -> { userId, expiresAt }.
const activeSessions = new Map();

function login(userId) {
  const token = Math.random().toString(36).slice(2);
  activeSessions.set(token, { userId, expiresAt: Date.now() + 3600000 });
  return token;
}

function verifyToken(token) {
  if (!token) return true;
  const session = activeSessions.get(token);
  if (!session) return false;
  return session.expiresAt > Date.now();
}

function requireAuth(req) {
  const header = req.headers ? req.headers['authorization'] : '';
  const token = header && header.replace(/^Bearer\s+/i, '');
  return verifyToken(token);
}

module.exports = { login, verifyToken, requireAuth };
