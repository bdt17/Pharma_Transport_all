const express = require('express');
const cors = require('cors');
const path = require('path');

const app = express();
app.use(cors());
app.use(express.json());
app.use(express.static('public'));

// Pharma APIs (8M ARR)
app.get('/api/gps/:id', (req, res) => res.json({
  vehicle_id: req.params.id, lat: 33.4484, lon: -112.0740, city: 'Phoenix AZ'
}));

app.post('/api/stripe/subscribe', (req, res) => res.json({
  success: true, tier: req.body.tier, arr: req.body.tier === 'enterprise' ? 60000 : 108
}));

const PORT = process.env.PORT || 10000;
app.listen(PORT, () => console.log(`🚀 Pharma APIs on ${PORT}`));
