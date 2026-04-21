const mongoose = require('mongoose');
(async () => {
  await mongoose.connect(process.env.MONGO_URI);
  const U = require('/app/src/models/hyUserModel');
  const u = await U.findOne({ userId: 'vpn1' }).lean();
  console.log(JSON.stringify({ enabled: u?.enabled, password: u?.password, nodes: u?.nodes }));
  await mongoose.disconnect();
})();
