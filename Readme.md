Cross Account Pipeline
============================

This repository is designed to help build out a cross account, cross region, pipeline in AWS. It also has the ability to support developer accounts, to facilitate developer testing and experimenting without impacting others.

![alt text](CrossAccountPipeline.png "Cross Account Pipeline Diagram")

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
- _BuildAccountKMSKeyArn_ - set this value to the `CrossAccountCMK` export value from the `CrossAccountPrimary` stack.
- _PipelineBucket_ - set this value to the `PipelineBucket` export value from the `CrossAccountPrimary` stack
- _SecondaryPipelineBucket_ - not used in the build account
- _SecondaryCrossAccountCMK_ - not used in the build account


## Cross Region

If any of your deployments are in regions other than the build region you will need perform an additional step for each region (NOTE: currently only one additional region is supported). These steps will need to be run once per region you are deploying to.

Create a stack using `CrossAccountRegional.yaml` in the build account, in the region you are deploying to. There is only one parameter:

- _DeploymentOrgPath_ - set this value to the paths (comma separated) to your deployment organizations (e.g. o-abcdefghij/r-h123/ou-h123-3zyxwvut/). These organization should contain all the accounts you want to deploy to.

## Deployment Accounts

Once the primary stack, and any regional stacks, are completed you will need to create a stack using `CrossAccountDeploy.yaml` in each of the accounts to which you wish to deploy (StackSets are a great way to do this, as all the values are the same). This stack can be created in any region because it only creates IAM resources, which are global. `us-east-1` is recommended. These are the paramters:

- _BuildAccount_ - set this value to the AWS Account ID of the build account
- _BuildAccountKMSKeyArn_ - set this value to the `CrossAccountCMK` export value from the `CrossAccountPrimary` stack.
- _PipelineBucket_ - set this value to the `PipelineBucket` export value from the `CrossAccountPrimary` stack
- _SecondaryPipelineBucket_ - (optional) if you have a secondary region you are deploying to set this to the `CrossAccountCMK` export value from the `CrossAccountRegional` stack for your secondary region.
- _SecondaryCrossAccountCMK_ - (optional) if you have a secondary region you are deploying to set this to the `PipelineBucket` export value from the `CrossAccountRegional` stack for your secondary region.

> NOTE: currently the `CrossAccountDeploy.yaml` only supports a two region deployment. I hope to expand upon that soon.


That is all that is needed to create a pipeline that is cross account/cross region. For an example pipeline that uses the values above please look at the `ExampleProjectPipelineSimple.yaml`.

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
- _BuildAccountKMSKeyArn_ - set this value to the `CrossAccountCMK` export value from the `CrossAccountDeveloper` stack.
- _PipelineBucket_ - set this value to the `PipelineBucket` export value from the `CrossAccountDeveloper` stack
- _SecondaryPipelineBucket_ - not used for developer accounts
- _SecondaryCrossAccountCMK_ - not used for developer accounts


Once this is done you will have a bucket that gets data both from your account's builds and the "real" build account's builds. This will keep your account in sync at all times, while allowing you to test on a private branches.

## Final Thoughts

Use the `ExampleProjectPipelineSimple.yaml` file as your baseline for building pipelines. There is one important element to this template that, left out, could cause builds to run on every developer's account. You'll notice the `Fn::If` statements on the builds. These are used to turn off the automatic webhooks for the developer accounts. If you are all using the same repository this is imporant. If you are using forks, where each developer is forking the main repository, they you can treat your account as though it is NOT a developer account.


Note On GitHub
----------------
The ExampleProject project uses a GitHub hook for CodeBuild. This hook uses an OAuth connection to AWS, so no GitHub credentials are stored in AWS. In order to configure this you'll need to go to the CodeBuild page and start the process of creating a build project. Follow the directions in [this article](https://www.itonaut.com/2018/06/18/use-github-source-in-aws-codebuild-project-using-aws-cloudformation/) for direction of what you need to do (just the last part of the article).
