const mongoose = require('mongoose');

(async () => {
  const userId = process.env.CELERITY_USER_ID || 'vpn1';
  await mongoose.connect(process.env.MONGO_URI);
  const U = require('/app/src/models/hyUserModel');
  const u = await U.findOne({ userId }).lean();
  console.log(JSON.stringify({ enabled: u?.enabled, password: u?.password, nodes: u?.nodes }));
  await mongoose.disconnect();
})();
