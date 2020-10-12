// Modify this function to get the bucket list from the above DynamoDB table
const AWS = require('aws-sdk')
const s3 = new AWS.S3({ region: 'us-east-1' });
const dynamoDB = new AWS.DynamoDB.DocumentClient();

exports.handler = async function main(event, context) {
  const destBuckets = await getDestinationBuckets();

  if (event.Records === null) {
    context.fail('Error: Event has no records.');
    return;
  }

  // Make a task for each combination of record and destBucket
  let tasks = [];
  for (let i = 0; i < event.Records.length; i++) {
    for (let j = 0; j < destBuckets.length; j++) {
      tasks.push(replicatePromise(event.Records[i], destBuckets[j]));
    }
  }

  await Promise.all(tasks);
};

async function getDestinationBuckets() {
  const input = {
    TableName: 'CrossAccountBuildReplication',
    IndexName: 'gsi1',
    KeyConditionExpression: '#pk = :pk AND begins_with(#sk, :begins)',
    ExpressionAttributeNames: {
      '#pk': 'gsi1_pk',
      '#sk': 'gsi1_sk'
    },
    ExpressionAttributeValues: {
      ':pk': 'ReplicateBuildArtifact',
      ':begins': 'Bucket|'
    }
  };

  const output = await dynamoDB.query(input).promise();

  return output.Items.map(i => i.bucketArn);
}

function replicatePromise(record, destBucket) {
  return new Promise((resolve, reject) => {
    // The source bucket and source key are part of the event data
    var srcBucket = record.s3.bucket.name;
    var srcKey = decodeURIComponent(record.s3.object.key.replace(/\+/g, " "));
    var srcVersion = record.s3.object.version;

    // Modify destKey if an alternate copy location is preferred
    var destKey = srcKey;
    var msg = 'copying ' + srcBucket + ':' + srcKey + ' to ' + destBucket + ':' + destKey;

    console.log('Attempting: ' + msg);
    s3.copyObject({
      Bucket: destBucket,
      Key: destKey,
      ACL: 'bucket-owner-full-control',
      CopySource: encodeURIComponent(srcBucket + '/' + srcKey + (srcVersion ? ('?versionId=' + srcVersion) : '')),
      MetadataDirective: 'COPY'
    }, (err, data) => {
      if (err) {
        console.log('Error:' + msg);
        console.log(err, err.stack); // an error occurred
        return reject('Error:' + msg);
      }
      else {
        console.log('Success: ' + msg);
        return resolve('Success: ' + msg);
      }
    });
  });
}
