const { BlobServiceClient, StorageSharedKeyCredential } = require('@azure/storage-blob');

// Polyfill for crypto if not available in Azure Functions runtime
if (typeof globalThis.crypto === 'undefined') {
  globalThis.crypto = require('crypto').webcrypto;
}

module.exports = async function (context, req) {
  context.log('Flights list function triggered');
  
  try {
    const accountName = process.env.AZURE_STORAGE_ACCOUNT;
    const accountKey = process.env.AZURE_STORAGE_KEY;
    const containerName = process.env.AZURE_STORAGE_CONTAINER || 'flights';

    context.log('Config:', { accountName, containerName, hasKey: !!accountKey });

    if (!accountName || !accountKey) {
      context.res = {
        status: 500,
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ error: 'Storage not configured' })
      };
      return;
    }

    const connectionString = `DefaultEndpointsProtocol=https;AccountName=${accountName};AccountKey=${accountKey};EndpointSuffix=core.windows.net`;
    const blobServiceClient = BlobServiceClient.fromConnectionString(connectionString);
    const containerClient = blobServiceClient.getContainerClient(containerName);
    
    const flights = [];
    for await (const blob of containerClient.listBlobsFlat()) {
      flights.push({
        name: blob.name,
        size: blob.properties.contentLength,
        lastModified: blob.properties.lastModified
      });
    }

    context.res = {
      status: 200,
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ flights, count: flights.length })
    };
  } catch (error) {
    context.log.error('Error:', error);
    context.res = {
      status: 500,
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ error: error.message, stack: error.stack })
    };
  }
};

