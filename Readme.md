Cross Account Pipeline
============================

This repository is designed to help build out a cross account, cross region, pipeline in AWS. It also has the ability to support developer accounts, to facilitate developer testing and experimenting without impacting others.

![alt text](CrossAccountPipeline.png "Cross Account Pipeline Diagram")

There are some known issues with this repository:
- There are permissions that are not nearly as tight as they should be. With time (and maybe some help) I hope to tighten these down to only grant what is absolutely necessary. Currently there is even a place where I have granted admin access, though that place already had permission to create IAM policies so it wasn't a big stretch.
- At times the example pipeline fails when starting in a region other than the primary region. The error message indicates that the artifacts aren't available or permissions don't allow access, but, without fail, it works when you retry. I'm going to reach out to AWS on this.

There are also some areas for improvement:
- A lot of the places where you have to put in ARNs could be generated with the help of a custom transform. For example, instead of supplying a list of buckets as well as the ARNs with /* you could just supply the buckets and use a transform to build the ARNs.
- Need to document the bootstrap and developer shell scripts.

Let's get to it
------------

In order to create the cross account pipeline you must follow the steps below *in order*.

Create a stack using `CrossAccountPrimary.yaml`. This should be run in the build account. This is the account where builds will run and the pipeline will live. This should be deployed in the region in which you want to perform builds and manage the pipeline. It does not need to be the same region as any of your deployments. There is only one parameter:

- _DeploymentOrgPath_ - set this value to the path to your deployment organization (e.g. o-abcdefghij/r-h123/ou-h123-3zyxwvut/)

Cross Region
----------------------------

If any of your deployments are in regions other than the build region you will need perform some additional steps. These steps will need to be run once per region you are deploying to.

Create a stack using `CrossAccountRegional.yaml` in the build account, in the region you are deploying to. There is only one parameter:

- _DeploymentOrgPath_ - set this value to the path to your deployment organization (e.g. o-abcdefghij/r-h123/ou-h123-3zyxwvut/)


Once the primary stack, and any regional stacks, are completed you will need to create a stack using `CrossAccountDeploy.yaml` in each of the accounts to which you wish to deploy (StackSets are a great way to do this, as all the values are the same). This stack can be created in any region because it only creates IAM resources, which are global. Most often this should be created in the same region as you are deploying to. These are the paramters:

- _BuildAccount_ - set this value to the AWS Account ID of the build account
- _BuildAccountKMSKeyArn_ - set this value to the `CrossAccountCMK` export value from the `CrossAccountPrimary` stack.
- _PipelineBucket_ - set this value to the `PipelineBucket` export value from the `CrossAccountPrimary` stack
- _SecondaryPipelineBucket_ - (optional) if you have a secondary region you are deploying to set this to the `CrossAccountCMK` export value from the `CrossAccountRegional` stack for your secondary region.
- _SecondaryCrossAccountCMK_ - (optional) if you have a secondary region you are deploying to set this to the `PipelineBucket` export value from the `CrossAccountRegional` stack for your secondary region.

> NOTE: currently the `CrossAccountDeploy.yaml` only supports a two region deployment. We hope to expand upon that soon.


That is all that is needed to create a pipeline that is cross account/cross region. For an example pipeline that uses the values above please look at the `ExampleProjectPipelineSimple.yaml`.

Developer Account
-----------------
If you are running in a developer account you'll want to take some steps to be sure things are always up to date in your account.

First, go through the steps of creating a cross account pipeline, treating your developer account as both the build account and the deployment account (you'll only deploy to one account), but you'll want to make a few small changes.

In the primary stack:
- you'll need to add the "real" build account's root account ARN to the _RootAccountArns_ parameter.

You'll also need to run the `CrossAccountDeveloper.yaml` in the developer account. It has one parameter:
- _ReplicationFunctionRoleArn_ - the role ARN from the primary account's replication function

In the "real" build account you'll need to modify the replication settings:
- add your artifact bucket to the _ReplicationBucketList_ parameter.
- add your artifact bucket to the _ReplicationBucketStarArns_ parameter.
- add your CMK to the _ReplicationCMKs_ parameter.

Once this is done you will have a bucket that gets data both from your account's builds and the "real" build account's builds. This will keep your account in sync at all times, whilst allowing you to test on a private fork.


Note On GitHub
----------------
The ExampleProject project uses a GitHub hook for CodeBuild. This hook uses an OAuth connection to AWS, so no GitHub credentials are stored in AWS. In order to configure this you'll need to go to the CodeBuild page and start the process of creating a build project. Follow the directions in [this article](https://www.itonaut.com/2018/06/18/use-github-source-in-aws-codebuild-project-using-aws-cloudformation/) for direction of what you need to do (just the last part of the article).

**_NOTE_**: Some of the permission grants in this code are beyond what you should grant. For example, in order to simplify the build/deploy the grants in the `CrossAccountDeploy.yaml` are very open (`CrossAccount-CloudFormationRole` is granted `arn:aws:iam::aws:policy/AdministratorAccess`). You should tighten these permissions to match the permissions you wish to have on your deployment process.
