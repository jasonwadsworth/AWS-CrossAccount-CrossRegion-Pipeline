Cross Account Pipeline
============================

This repository is designed to help build out a cross account, cross region, pipeline in AWS. It also has the ability to support developer accounts, to facilitate developer testing and experimenting without impacting others.

![alt text](CrossAccountPipeline.png "Cross Account Pipeline Diagram")

> Looking for the previous version of this project? You can find it [here](https://github.com/jasonwadsworth/AWS-CrossAccount-CrossRegion-Pipeline/releases/tag/1.0.0). That version is no longer being maintained, but feel free to make your own copy of it.

There are definitely some areas for improvement:
- The current version doesn't handle more than two regions. This is a limitation that can be remedied by simply adding to the `CrossAccountDeploy.yaml` file. Ideally it would use a transform so you don't have to add a new parameter for each region, but that might not be so easy.
- There needs to be some documentation on how this uses organization. This version relies heavily on organizations for managing access to the artifact buckets and KMS key. This greatly simplifies things, but it needs to be documented.

---
## Using the infrastructure

Before getting started, there are a few things you should know to help you understand the infrastructure.

### Roles and Policies
There are several roles and policies that are created for you to use, as well as some requirements for roles/policies you create.

- Paths - all roles created by, and used in, this infrastructre have a path of `/cross-account-service-role/`. This path is important because it is used to grant permissions to things. When you create a deploy project one of the things you'll need to do is create a permissions template for deploying your service. The role created in this step must use this path.
- CrossAccount-PipelineSource - this role is used as the source for a pipeline. This role is an output of the primary stack, but it is not exported. It is a named resource, so you can reference it by name in your templates. `!Sub arn:aws:iam::${AWS::AccountId}:role/cross-account-service-role/CrossAccount-PipelineSource`
- Every account to which you deploy will have a few roles that are used for different parts of the process.
    - CrossAccount-CodePipeline - this role is what CodePipeline uses to execute the different actions. The role has permissions that are generally limited to things that CodePipeline needs to do, like create/update/delete a CloudFormation stack, or run a CodeBuild. It also has the ability to assume and pass the relavent roles. You can reference this role by name like this (where `DevAccount` is a parameter of your stack): `!Sub arn:aws:iam::${DevAccount}:role/cross-account-service-role/CrossAccount-CodePipeline`
    - CrossAccount-CodeBuild - this role is used for any CodeBuild projects that live in the build account. You can reference this role by name like this: `!Sub arn:aws:iam::${AWS::AccountId}:role/cross-account-service-role/CrossAccount-CodeBuild`
    - CrossAccount-CloudFormation-PolicyBuilder - this role is the most powerful role in the process, as it has permissions to create roles and policies that are used to deploy your infrastructure. When you create a deployment pipeline you will include a step that creates a role that is used by the following steps. This policy builder allows you to limit the scope of what you are allowed to deploy. Given it's power, the results of this step should be monitored to be sure you aren't allowing undesired escalations. You can reference this role by name like this (where `DevAccount` is a parameter of your stack): `!Sub arn:aws:iam::${DevAccount}:role/cross-account-service-role/CrossAccount-CloudFormation-PolicyBuilder`
    - CrossAccount-UpdatePipeline - this role is used to update the pipeline itself. It is used in the `CreateUpdatePipelineChangeSet` and `ExecuteUpdatePipelineChangeSet` of a pipeline (this are typical actions, though not required). You can reference this role by name like this: `!Sub arn:aws:iam::${AWS::AccountId}:role/cross-account-service-role/CrossAccount-UpdatePipeline`

---
## Getting started

In order to create the cross account pipeline you must follow the steps below *in order*.

Create a stack using `CrossAccountPrimary.yaml`. This should be run in the build account. This is the account where builds will run and the pipeline will live. This should be deployed in the region in which you want to perform builds and manage the pipeline. It does not need to be the same region as any of your deployments (though currently it does need to be one of the two regions you support). There is only one parameter:

- _DeploymentOrgPath_ - set this value to the paths (comma separated) to your deployment organizations (e.g. o-abcdefghij/r-h123/ou-h123-3zyxwvut/). These organization should contain all the accounts you want to deploy to.


Once the primary stack is completed you will need to create a stack using `CrossAccountDeploy.yaml` in the build account. These are the paramters:

- _BuildAccount_ - set this value to the AWS Account ID of the build account
- _BuildAccountKMSKeyArns_ - set this value to the `CrossAccountCMK` export value from the `CrossAccountPrimary` stack.
- _PipelineBuckets_ - set this value to the `PipelineBucket` export value from the `CrossAccountPrimary` stack


## Cross Region

If any of your deployments are in regions other than the build region you will need perform an additional step for each region (NOTE: currently only one additional region is supported). These steps will need to be run once per region you are deploying to.

Create a stack using `CrossAccountRegional.yaml` in the build account, in the region you are deploying to. There is only one parameter:

- _DeploymentOrgPath_ - set this value to the paths (comma separated) to your deployment organizations (e.g. o-abcdefghij/r-h123/ou-h123-3zyxwvut/). These organization should contain all the accounts you want to deploy to.

## Deployment Accounts

Once the primary stack, and any regional stacks, are completed you will need to create a stack using `CrossAccountDeploy.yaml` in each of the accounts to which you wish to deploy (StackSets are a great way to do this, as all the values are the same). This stack can be created in any region because it only creates IAM resources, which are global. `us-east-1` is recommended. These are the paramters:

- _BuildAccount_ - set this value to the AWS Account ID of the build account
- _BuildAccountKMSKeyArns_ - set this value to a comma separated list of the `CrossAccountCMK` export value from the `CrossAccountPrimary` stack, followed by the `CrossAccountCMK` export value from each of the `CrossAccountRegional` stacks.
- _PipelineBuckets_ - set this value to a comma separated list of the `PipelineBucket` export value from the `CrossAccountPrimary` stack, followed by the `PipelineBucket` export value from each of the `CrossAccountRegional` stack

## Helper Macros

In order to make building your pipelines a little easier I've included a couple of macro functions that will take care of duplicating stages as well as taking care of the artificts stores. To use the macros you'll need to create a stack using `CrossAccountHelperMacros.yaml` in the account and region of the pipelines (the primary region).

### PipelineHelper Macro

To use this macro you add the following to your pipeline resource:

```
    Fn::Transform:
      Name: CrossAccount-PipelineHelperMacro
      Parameters:
        Names:
            - String
        Accounts:
            - String
        Regions:
            - String
        ArtifactBuckets:
            - String
        ArtifactKMSKeys:
            - String
        ManualApprovalNames:
            - String
        ApprovalNotificationArn: String
        DuplicateStages:
            - String
```

- _Names_: Array of names to use when duplicating. This value can be omitted if you have a stack parameter by the same name.
- _Accounts_: Array of accounts to use when duplicating. This value can be omitted if you have a stack parameter by the same name. The order and length of the accounts must match that of the names.
- _Regions_: Array of regions to use when duplicating. This value can be omitted if you have a stack parameter by the same name. The order and length of the regions must match that of the names. If you are deploying multiple times to the same region the region should be included multiple times.
- _ArtifactBuckets_: Array of artifact buckets. This value can be omitted if you have a stack parameter by the same name. The order of the buckets must match the order of the artifact regions.
- _ArtifactKMSKeys_: Array of artifact KMS key ARNs. This value can be omitted if you have a stack parameter by the same name. The order of the ARNs must match the order of the artifact regions.
- _ArtifactRegions_: Array of artifact buckets. This value can be omitted if you have a stack parameter by the same name.
- _ManualApprovalNames_: Array of the names (from the duplicate names above) that should have a manual approval action added.
- _ApprovalNotificationArn_: The ARN of the approval SNS topic.
- _DuplicateStages_: Array of the stages to duplicate. Each stage in the array will result in one stage for each name above.

That is all that is needed to create a pipeline that is cross account/cross region.

### PipelineHelper2 Macro

This macro allows you to configure your Pipeline stages to run "waves", or collections of environments in parallel. For example, say you have a dev environment, two testing environments and two production environments. With this macro you can deploy the dev by itself, the two test environments in parallel, followed by the two production environments in parallel. To configure this there is a JSON object that you'll place in SSM Parameter Store and reference in the configuration. The parameter name must begin with `/cross-account-pipeline-helper/` in order for the macro to have access to it.

To use this macro you add the following to your pipeline resource:

```
    Fn::Transform:
      Name: CrossAccount-PipelineHelper2Macro
      Parameters:
        ArtifactBuckets:
            - String
        ArtifactKMSKeys:
            - String
        ApprovalNotificationArn: String
        ConfigParameterName: String
```

- _ArtifactBuckets_: Array of artifact buckets. This value can be omitted if you have a stack parameter by the same name. The order of the buckets must match the order of the artifact regions.
- _ArtifactKMSKeys_: Array of artifact KMS key ARNs. This value can be omitted if you have a stack parameter by the same name. The order of the ARNs must match the order of the artifact regions.
- _ArtifactRegions_: Array of artifact buckets. This value can be omitted if you have a stack parameter by the same name.
- _ApprovalNotificationArn_: The ARN of the approval SNS topic.
- _ConfigParameterName_: The name of the SSM Parameter Store parameter that holds the configuration JSON

NOTE: you must include an artifact region, and related bucket and key, for any region that is included in your deployment configuration.

The JSON has the following structure:

```json
[
    {
        "stage": "Deploy", // the stage in your CodePipeline template that you want to duplicate
        "waves": [ // a wave is a collection of environments that can be deployed in parallel
            {
                "name": "Development", // the name of the wave - this will be added to the stage name
                "manualApproval": false, // optional, defaults to false - setting to true will add a manual intervention step at the front of the wave
                "environments": [ // the environments to include in the wave
                    {
                        "name": "dev",             // the name of the environment - this will be used to replace anything with {NAME} in the stage
                        "account": "123000321000", // the account of the environment - this will be used to replace anything with {ACCOUNT_ID} in the stage
                        "region": "us-west-2"      // the region of the environment - this will be used to replace anything with {REGION} in the stage
                    }
                ]
            },
            {
                "name": "Test",
                "manualApproval": true,
                "environments": [
                    {
                        "name": "qa1",
                        "account": "143000341000",
                        "region": "us-west-2"
                    },
                    {
                        "name": "qa2",
                        "account": "341000143000",
                        "region": "ap-southeast-1"
                    }
                ]
            },
            {
                "name": "Production",
                "manualApproval": true,
                "environments": [
                    {
                        "name": "prod",
                        "account": "062820050000",
                        "region": "us-west-2"
                    },
                    {
                        "name": "apac",
                        "account": "000006282005",
                        "region": "ap-southeast-1"
                    }
                ]
            }
        ]
    }
]
```

---
## Developer Account

If you want to support replication to developer accounts, there are a few additional things you'll need to do.

First, you need to have organizations configured and have all of your developer accounts in the same organization.

Next, you'll need to create a stack using `CrossAccountDeveloperReplicate.yaml` in the build account, in the same region as your primary stack. There is only one parameter:

- _DeveloperOrgPath_ - set this value to the path to your developer organization (e.g. o-abcdefghij/r-h123/ou-h123-3srqponml/). This organization should include all the developer accounts you want to automatically sync.

Once that is done you can create a stack using `CrossAccountDeveloper.yaml` in a developer account. Currently this stack has to be in the same region as the primary stack in the build account. This stack has three parameters:

- _BuildAccountId_ - set this value to the AWS account ID of the build account
- _ReplicationRegistrationTopicArn_ - set this value to the output value by the same name, from the replicate stack in the build account.
- _ReplicationRoleArn_ - set this value to the output value by the same name, from the replicate stack in the build account.

Once your developer stack is done you'll need to create a stack using `CrossAccountDeploy.yaml`. This is the same stack you used above, for deploying to your different accounts. It has the following parmeters:

- _BuildAccount_ - set this value to the AWS Account ID of the DEVELOPER account. Your developer account will be a build account just for you
- _BuildAccountKMSKeyArns_ - set this value to the `CrossAccountCMK` export value from the `CrossAccountDeveloper` stack.
- _PipelineBuckets_ - set this value to the `PipelineBucket` export value from the `CrossAccountDeveloper` stack

You'll also need to create the macro stack if you are using that. See above for more info.

Once this is done you will have a bucket that gets data both from your account's builds and the "real" build account's builds. This will keep your account in sync at all times, while allowing you to test on a private branches.
