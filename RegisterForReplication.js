const AWS = require('aws-sdk')
const dynamoDB = new AWS.DynamoDB.DocumentClient();

exports.handler = async function main(event, context) {
  try {
    const id = event.PhysicalResourceId || (Math.random().toString(36).substring(2, 16) + Math.random().toString(36).substring(2, 16)).toUpperCase();

    if (event.RequestType === 'Create') {
      await dynamoDB.put({
        ConditionExpression: `attribute_not_exists(pk)`,
        TableName: 'CrossAccountBuildReplication',
        Item: {
          pk: id,
          sk: 'Primary',
          gsi1_pk: 'ReplicateBuildArtifact',
          gsi1_sk: `Bucket|${id}`,
          id: id,
          bucketArn: event.ResourceProperties.BucketArn,
          accountId: event.ResourceProperties.AccountId,
          region: event.ResourceProperties.Region
        }
      }).promise();
    }
    else if (event.RequestType === 'Update') {
      await dynamoDB.put({
        ConditionExpression: `attribute_exists(pk)`,
        TableName: 'CrossAccountBuildReplication',
        Item: {
          pk: id,
          sk: 'Primary',
          gsi1_pk: 'ReplicateBuildArtifact',
          gsi1_sk: `Bucket|${id}`,
          id: id,
          bucketArn: event.ResourceProperties.BucketArn,
          accountId: event.ResourceProperties.AccountId,
          region: event.ResourceProperties.Region
        }
      }).promise();
    }
    else if (event.RequestType === 'Delete') {
      await dynamoDB.delete({
        TableName: 'CrossAccountBuildReplication',
        Key: {
          "pk": id,
          sk: 'Primary'
        }
      }).promise();
    }
    else {
      return {
        Status: "FAILED",
        reason: `Unknown RequestType '${event.RequestType}'`
      };
    }

    return {
      Status: "SUCCESS",
      PhysicalResourceId: id,
      Data: {
        Name: "TheName"
      }
    };
  }
  catch (e) {
    console.error(e);
    return {
      Status: "FAILED",
      reason: `Error registering.`
    };
  }
};
