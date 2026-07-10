require('dotenv').config();

const fs = require('fs');
const path = require('path');
const express = require('express');
const mongoose = require('mongoose');
const Stats = require('./models/Stats');

const PORT = process.env.PORT || 4000;
const MONGO_URI = process.env.MONGO_URI || 'mongodb://localhost:27017/oa_checker';
const ADMIN_KEY = process.env.ADMIN_KEY;
// Base origin (scheme + host, no path) this server is reachable at from a
// candidate's laptop. Used only to tell the check scripts where to send
// their pass/fail ping. Defaults to plain localhost for local dev.
const PUBLIC_URL = process.env.PUBLIC_URL || `http://localhost:${PORT}`;
const REPORT_URL = `${PUBLIC_URL}/oa-check/report`;

const app = express();
app.use(express.json());

const router = express.Router();

router.get('/health', (req, res) => {
  res.json({ status: 'ok' });
});

function serveScript(scriptFile, contentType) {
  return (req, res) => {
    const raw = fs.readFileSync(path.join(__dirname, 'scripts', scriptFile), 'utf8');
    res.type(contentType).send(raw.replace('__REPORT_URL__', REPORT_URL));
  };
}

router.get('/check.sh', serveScript('check.sh', 'text/x-sh'));
router.get('/check.ps1', serveScript('check.ps1', 'text/plain'));

// Single URL for both platforms: PowerShell's Invoke-RestMethod/iwr identify
// themselves in the User-Agent, curl does not carry OS info either way, so
// "PowerShell" in the UA is the reliable signal to pick the .ps1 script.
router.get('/check', (req, res) => {
  const ua = req.get('user-agent') || '';
  if (/powershell/i.test(ua)) {
    serveScript('check.ps1', 'text/plain')(req, res);
  } else {
    serveScript('check.sh', 'text/x-sh')(req, res);
  }
});

router.post('/report', async (req, res) => {
  const { platform, passed } = req.body || {};
  if (typeof platform !== 'string' || typeof passed !== 'boolean') {
    return res.status(400).json({ error: 'Invalid report payload' });
  }
  const date = new Date().toISOString().slice(0, 10);
  await Stats.findOneAndUpdate(
    { date, platform },
    { $inc: { total: 1, passed: passed ? 1 : 0, failed: passed ? 0 : 1 } },
    { upsert: true }
  );
  res.json({ received: true });
});

function requireAdminKey(req, res, next) {
  if (!ADMIN_KEY || req.get('x-admin-key') !== ADMIN_KEY) {
    return res.status(401).json({ error: 'Unauthorized' });
  }
  next();
}

router.get('/stats', requireAdminKey, async (req, res) => {
  const stats = await Stats.find().sort({ date: -1, platform: 1 });
  res.json(stats);
});

app.use('/oa-check', router);

mongoose
  .connect(MONGO_URI)
  .then(() => {
    console.log('Connected to MongoDB');
    app.listen(PORT, () => {
      console.log(`Server listening on http://localhost:${PORT}`);
    });
  })
  .catch((err) => {
    console.error('MongoDB connection error:', err);
    process.exit(1);
  });
