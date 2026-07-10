const mongoose = require('mongoose');

const statsSchema = new mongoose.Schema({
  date: { type: String, required: true },
  platform: { type: String, required: true },
  total: { type: Number, default: 0 },
  passed: { type: Number, default: 0 },
  failed: { type: Number, default: 0 },
});
statsSchema.index({ date: 1, platform: 1 }, { unique: true });

module.exports = mongoose.model('Stats', statsSchema);
