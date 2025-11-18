const { BlobServiceClient } = require('@azure/storage-blob');
const { DefaultAzureCredential } = require('@azure/identity');

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

    if (!accountName) {
      context.res = {
        status: 500,
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ error: 'Storage account not configured' })
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

