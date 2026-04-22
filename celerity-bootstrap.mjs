import crypto from 'node:crypto';
import mongoose from 'mongoose';
import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);

(async () => {
  const uri = process.env.MONGO_URI;
  if (!uri) {
    throw new Error('MONGO_URI is required');
  }
  await mongoose.connect(uri);
  const Admin = require('/app/src/models/adminModel');
  const ApiKey = require('/app/src/models/apiKeyModel');

  let adminPassword = '';
  if (!(await Admin.hasAdmin())) {
    adminPassword = crypto.randomBytes(12).toString('base64url');
    await Admin.createAdmin('paneladmin', adminPassword);
    console.error('[bootstrap] Created admin: paneladmin');
  } else {
    console.error('[bootstrap] Admin already exists');
  }

  await ApiKey.deleteMany({ name: 'bootstrap-agent' });
  const { plainKey } = await ApiKey.createKey({
    name: 'bootstrap-agent',
    scopes: ['users:read', 'users:write', 'nodes:read', 'nodes:write', 'stats:read', 'sync:write'],
    createdBy: 'bootstrap',
  });

  console.log(JSON.stringify({ adminPassword, apiKey: plainKey }));
  await mongoose.disconnect();
})().catch((e) => {
  console.error(e);
  process.exit(1);
});
