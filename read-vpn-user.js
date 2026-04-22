const mongoose = require('mongoose');

(async () => {
  if (!process.env.MONGO_URI) {
    throw new Error('MONGO_URI is required');
  }
  const userId = process.env.CELERITY_USER_ID || 'vpn1';
  const showPassword = process.env.CELERITY_SHOW_PASSWORD === '1';
  await mongoose.connect(process.env.MONGO_URI);
  const U = require('/app/src/models/hyUserModel');
  const u = await U.findOne({ userId }).lean();
  console.log(JSON.stringify({
    enabled: u?.enabled,
    password: showPassword ? u?.password : undefined,
    nodes: u?.nodes,
  }));
  await mongoose.disconnect();
})().catch((e) => {
  console.error(e);
  process.exit(1);
});
