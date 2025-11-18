const { BlobServiceClient } = require('@azure/storage-blob');
const { DefaultAzureCredential } = require('@azure/identity');

// Polyfill for crypto if not available in Azure Functions runtime
if (typeof globalThis.crypto === 'undefined') {
  globalThis.crypto = require('crypto').webcrypto;
}

module.exports = async function (context, req) {
  context.log('Flights create function triggered');
  
  if (req.method !== 'POST') {
    context.res = {
      status: 405,
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ error: 'Method not allowed' })
    };
    return;
  }

  try {
    const accountName = process.env.AZURE_STORAGE_ACCOUNT;
    const accountKey = process.env.AZURE_STORAGE_KEY;
    const containerName = process.env.AZURE_STORAGE_CONTAINER || 'flights';

    if (!accountName) {
      context.res = {
        status: 500,
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ error: 'Storage account not configured' })
      };
      return;
    }

    const flight = req.body;
    if (!flight.flightId || !flight.status) {
      context.res = {
        status: 400,
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ error: 'Missing required fields' })
      };
      return;
    }

    let blobServiceClient;
    
    // Try Azure AD first, fall back to shared key if available
    if (!accountKey) {
      context.log('Using Azure AD authentication');
      const credential = new DefaultAzureCredential();
      blobServiceClient = new BlobServiceClient(
        `https://${accountName}.blob.core.windows.net`,
        credential
      );
    } else {
      context.log('Using shared key authentication');
      const connectionString = `DefaultEndpointsProtocol=https;AccountName=${accountName};AccountKey=${accountKey};EndpointSuffix=core.windows.net`;
      blobServiceClient = BlobServiceClient.fromConnectionString(connectionString);
    }
    
    const containerClient = blobServiceClient.getContainerClient(containerName);
    
    await containerClient.createIfNotExists();

    const blobName = `${flight.flightId}.json`;
    const blockBlobClient = containerClient.getBlockBlobClient(blobName);
    
    const content = JSON.stringify(flight, null, 2);
    await blockBlobClient.upload(content, content.length, {
      blobHTTPHeaders: { blobContentType: 'application/json' }
    });

    context.res = {
      status: 200,
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ success: true, blobName })
    };
  } catch (error) {
    context.log.error('Error:', error);
    context.res = {
      status: 500,
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ error: error.message })
    };
  }
};
