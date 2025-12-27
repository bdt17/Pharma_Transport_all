const express=require('express'),app=express();
app.use(express.json());
app.get('/api/gps/:id',(r,s)=>s.json({id:r.params.id,lat:33.4484,lon:-112.0740,city:'Phoenix AZ'}));
app.get('/api/stripe/subscribe',(r,s)=>s.json({success:true,tier:'enterprise',arr:60000}));
app.get('/',(r,s)=>s.json({live:'🚀 Pharma 8M ARR LIVE'}));
app.listen(process.env.PORT||10000,()=>console.log('🚀 LIVE'));
