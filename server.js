require('dotenv').config();

const fs = require('fs');
const path = require('path');
const express = require('express');
const mongoose = require('mongoose');
const Stats = require('./models/Stats');

const PORT = process.env.PORT || 4000;
const MONGO_URI = process.env.MONGO_URI || 'mongodb://localhost:27017/oa_checker';
const ADMIN_KEY = process.env.ADMIN_KEY;

const app = express();
// Trust the X-Forwarded-* headers Nginx sets, so req.protocol reflects the
// scheme the candidate actually used (http vs https), not the internal
// Nginx-to-Node hop (which is always plain http).
app.set('trust proxy', true);
app.use(express.json());

const router = express.Router();

router.get('/health', (req, res) => {
  res.json({ status: 'ok' });
});

// A real browser's User-Agent always contains "Mozilla" plus a rendering
// engine token; curl, PowerShell's Invoke-RestMethod/iwr, and wget don't
// look like that. Used to stop students who paste the URL directly into a
// browser from getting a nicely rendered view of the whole script - it does
// nothing against someone deliberately running curl themselves, which is
// unavoidable for any script that has to execute on their own machine.
function looksLikeBrowser(ua) {
  return /mozilla/i.test(ua) && /chrome|safari|firefox|edg|opr/i.test(ua) &&
    !/powershell|curl|wget/i.test(ua);
}

function serveScript(scriptFile, contentType) {
  return (req, res) => {
    const ua = req.get('user-agent') || '';
    if (looksLikeBrowser(ua)) {
      return res
        .type('text/plain')
        .status(200)
        .send('Run the command your invigilator gave you from a Terminal (Mac/Linux) or PowerShell (Windows) window - this page does nothing on its own.');
    }
    // Derive the report URL from whatever host/scheme the candidate actually
    // used to fetch this script, instead of a fixed env var - that way it's
    // always correct regardless of which domain/IP points at this server.
    const reportUrl = `${req.protocol}://${req.get('host')}/oa-check/report`;
    const raw = fs.readFileSync(path.join(__dirname, 'scripts', scriptFile), 'utf8');
    res.type(contentType).send(raw.replace('__REPORT_URL__', reportUrl));
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
