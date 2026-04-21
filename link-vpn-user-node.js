const mongoose = require('mongoose');

(async () => {
  const uri = process.env.MONGO_URI;
  await mongoose.connect(uri);
  const HyUser = require('/app/src/models/hyUserModel');
  const cache = require('/app/src/services/cacheService');
  const nodeId = new mongoose.Types.ObjectId('69c971677e39e4a0d87cfeaa');
  const u = await HyUser.findOneAndUpdate(
    { userId: 'vpn1' },
    { $set: { nodes: [nodeId] } },
    { new: true }
  );
  if (u && u.subscriptionToken) {
    await cache.invalidateUser('vpn1');
    await cache.invalidateSubscription(u.subscriptionToken);
  }
  console.log('updated', u ? u.userId : 'none');
  await mongoose.disconnect();
})().catch((e) => {
  console.error(e);
  process.exit(1);
});
