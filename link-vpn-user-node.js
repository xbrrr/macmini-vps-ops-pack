const mongoose = require('mongoose');

(async () => {
  const uri = process.env.MONGO_URI;
  const userId = process.env.CELERITY_USER_ID || 'vpn1';
  const nodeIdValue = process.env.CELERITY_NODE_ID;

  if (!uri) {
    throw new Error('MONGO_URI is required');
  }
  if (!nodeIdValue) {
    throw new Error('CELERITY_NODE_ID is required');
  }
  if (!mongoose.Types.ObjectId.isValid(nodeIdValue)) {
    throw new Error('CELERITY_NODE_ID must be a valid Mongo ObjectId');
  }

  await mongoose.connect(uri);
  const HyUser = require('/app/src/models/hyUserModel');
  const cache = require('/app/src/services/cacheService');
  const nodeId = new mongoose.Types.ObjectId(nodeIdValue);
  const u = await HyUser.findOneAndUpdate(
    { userId },
    { $set: { nodes: [nodeId] } },
    { new: true }
  );
  if (u && u.subscriptionToken) {
    await cache.invalidateUser(userId);
    await cache.invalidateSubscription(u.subscriptionToken);
  }
  console.log('updated', u ? u.userId : 'none');
  await mongoose.disconnect();
})().catch((e) => {
  console.error(e);
  process.exit(1);
});
