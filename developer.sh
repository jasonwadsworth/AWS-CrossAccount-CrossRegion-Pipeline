#!/bin/bash

set -e

echo "The first step is to create the primary stack in your dev account. "


read -p 'Build account profile: ' real_build_account_profile

read -p 'Build account primary region: ' real_build_account_region

read -p 'Build account number: ' real_build_account

read -p 'Developer profile [default]: ' profile
profile=${profile:-"default"}

read -p 'Developer region [us-east-1]: ' region
region=${region:-"us-east-1"}

read -p 'Developer account number: ' build_account

read -p 'Deployment name [Development]: ' deploy_name
deploy_name=${deploy_name:-"Development"}

parameter_name="/CrossAccountPipeline/${deploy_name}Account"
parameter_description="The AccountId of the ${deploy_name} account for cross account pipelines."
aws ssm put-parameter --profile $profile --region $region --name $parameter_name --value $build_account --type "String" --no-overwrite --description $parameter_description

root_account_arns="arn:aws:iam::${build_account}:root,arn:aws:iam::${real_build_account}:root"

deploy_accounts=( "${build_account}")
deploy_regions=( "${region}" )
deploy_profiles=( "${profile}" )

primary_stack_name="CrossAccountPrimary"
deploy_stack_name="CrossAccountDeploy"
regional_stack_name="CrossAccountRegional"
developer_stack_name="CrossAccountDeveloper"

echo 'Creating primary cloud formation stack'
aws cloudformation create-stack \
    --profile $profile \
    --region $region \
    --stack-name $primary_stack_name \
    --template-body file://CrossAccountPrimary.yaml \
    --parameters \
        ParameterKey=RootAccountArns,ParameterValue=\"$root_account_arns\" \
    --capabilities CAPABILITY_NAMED_IAM


echo 'Waiting for primary stack to complete. This will take several minutes.'
aws cloudformation wait stack-create-complete --stack-name $primary_stack_name --profile $profile --region $region
echo 'Primary stack complete.'

echo 'Retrieving stack info.'
stack_info=$(aws cloudformation describe-stacks --stack-name $primary_stack_name --profile $profile --region $region)

# Get the CMK and pipeline bucket and build bucket outputs
primary_region_cmk=$(echo ${stack_info} | jq -r '.Stacks[0].Outputs[] | select( .OutputKey == "CMK" ) | .OutputValue ' )
primary_pipeline_bucket=$(echo ${stack_info} | jq -r '.Stacks[0].Outputs[] | select( .OutputKey == "PipelineBucket" ) | .OutputValue ' )
build_bucket=$(echo ${stack_info} | jq -r '.Stacks[0].Outputs[] | select( .OutputKey == "BuildBucket" ) | .OutputValue ' )

pipeline_bucket_access_role_arns=""

deployed_accounts=()

len=${#deploy_accounts[@]}
for (( i=0; i<$len; i++ ))
do
    if [[ " ${deployed_accounts[*]} " == *"${deploy_accounts[$i]}"* ]]
    then
        echo "Skipping ${deploy_accounts[$i]}; already created."
    else
        echo "Creating deployer stack in account ${deploy_accounts[$i]}"

        deploy_region="${deploy_regions[$i]}"
        deploy_profile="${deploy_profiles[$i]}"
        aws cloudformation create-stack \
            --profile $deploy_profile \
            --region $deploy_region \
            --stack-name $deploy_stack_name \
            --template-body file://CrossAccountDeploy.yaml \
            --parameters \
                ParameterKey=BuildAccount,ParameterValue=$build_account \
                ParameterKey=CMKARNs,ParameterValue=$primary_region_cmk \
            --capabilities CAPABILITY_NAMED_IAM

        deployed_accounts+="${deploy_accounts[$i]}"

        if [ $i != 0 ]
        then
            pipeline_bucket_access_role_arns="${pipeline_bucket_access_role_arns},";
        fi

        pipeline_bucket_access_role_arns="${pipeline_bucket_access_role_arns}arn:aws:iam::${deploy_accounts[$i]}:role/CrossAccountCodePipeline,arn:aws:iam::${deploy_accounts[$i]}:role/CrossAccountCloudFormation"
    fi
done


echo 'Waiting for deployer stacks to complete. This may take several minutes.'

len=${#deploy_accounts[@]}
for (( i=0; i<$len; i++ ))
do
    aws cloudformation wait stack-create-complete --stack-name $deploy_stack_name --profile $deploy_profile --region $deploy_region
done

pipeline_bucket_star_arns="arn:aws:s3:::${primary_pipeline_bucket}/*"

echo "Updating primary stack"
aws cloudformation update-stack \
    --profile $profile \
    --region $region \
    --stack-name $primary_stack_name \
    --use-previous-template \
    --parameters \
        ParameterKey=RootAccountArns,UsePreviousValue=true \
        ParameterKey=DeployReady,ParameterValue="true" \
        ParameterKey=PipelineBucketAccessRoleArns,ParameterValue=\"$pipeline_bucket_access_role_arns\" \
        ParameterKey=PipelineBucketStarArns,ParameterValue=\"$pipeline_bucket_star_arns\" \
        ParameterKey=PipelineCMKs,ParameterValue=\"$primary_region_cmk\" \
    --capabilities CAPABILITY_NAMED_IAM

echo "Waiting for primary stack update to complete. This will take several minutes."
aws cloudformation wait stack-update-complete --stack-name $primary_stack_name --profile $profile --region $region


echo "Retrieving information from build account"
stack_info=$(aws cloudformation describe-stacks --stack-name $primary_stack_name --profile $real_build_account_profile --region $real_build_account_region)

replication_function_role_arn=$(echo ${stack_info} | jq -r '.Stacks[0].Outputs[] | select( .OutputKey == "ReplicationRoleArn" ) | .OutputValue ' )
current_replication_bucket_list=$(echo ${stack_info} | jq -r '.Stacks[0].Parameters[] | select( .ParameterKey == "ReplicationBucketList" ) | .ParameterValue ' )
current_replication_bucket_star_arns=$(echo ${stack_info} | jq -r '.Stacks[0].Parameters[] | select( .ParameterKey == "ReplicationBucketStarArns" ) | .ParameterValue ' )
current_replication_cmks=$(echo ${stack_info} | jq -r '.Stacks[0].Parameters[] | select( .ParameterKey == "ReplicationCMKs" ) | .ParameterValue ' )

if [ "${current_replication_bucket_list}" != "" ]
then
    current_replication_bucket_list="${current_replication_bucket_list},"
    current_replication_bucket_star_arns="${current_replication_bucket_star_arns},"
    current_replication_cmks="${current_replication_cmks},"
fi

new_replication_bucket_list="${current_replication_bucket_list}${build_bucket}"
new_replication_bucket_star_arns="${current_replication_bucket_star_arns}arn:aws:s3:::${build_bucket}/*"
new_replication_cmks="${current_replication_cmks}${primary_region_cmk}"

echo 'Creating developer stack'
aws cloudformation create-stack \
    --profile $profile \
    --region $region \
    --stack-name $developer_stack_name \
    --template-body file://CrossAccountDeveloper.yaml \
    --parameters \
        ParameterKey=ReplicationFunctionRoleArn,ParameterValue=\"$replication_function_role_arn\"

echo "Waiting for developer stack create to complete. This may take several minutes."
aws cloudformation wait stack-create-complete --stack-name $developer_stack_name --profile $profile --region $region


echo "Updating build account primary stack"
aws cloudformation update-stack \
    --profile $real_build_account_profile \
    --region $real_build_account_region \
    --stack-name $primary_stack_name \
    --use-previous-template \
    --parameters \
        ParameterKey=RootAccountArns,UsePreviousValue=true \
        ParameterKey=DeployReady,UsePreviousValue=true \
        ParameterKey=PipelineBucketAccessRoleArns,UsePreviousValue=true \
        ParameterKey=PipelineBucketStarArns,UsePreviousValue=true \
        ParameterKey=PipelineCMKs,UsePreviousValue=true \
        ParameterKey=EnableReplication,ParameterValue="true" \
        ParameterKey=ReplicationBucketList,ParameterValue=\"$new_replication_bucket_list\" \
        ParameterKey=ReplicationBucketStarArns,ParameterValue=\"$new_replication_bucket_star_arns\" \
        ParameterKey=ReplicationCMKs,ParameterValue=\"$new_replication_cmks\" \
    --capabilities CAPABILITY_NAMED_IAM

echo "Waiting for build account primary stack update to complete. This will take several minutes."
aws cloudformation wait stack-update-complete --stack-name $primary_stack_name --profile $real_build_account_profile --region $real_build_account_region

