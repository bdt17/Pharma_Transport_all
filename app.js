const express = require('express');
const app = express();
app.use(express.json());
app.get('/api/gps/:id', (req, res) => res.json({
  id: req.params.id, lat: 33.4484, lon: -112.0740, city: 'Phoenix AZ'
}));
app.get('/', (req, res) => res.json({live: '🚀 Pharma 8M ARR'}));
app.listen(process.env.PORT || 10000, () => console.log('🚀 LIVE'));
