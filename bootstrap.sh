#!/bin/bash

set -e

read -p 'Build profile [default]: ' profile
profile=${profile:-"default"}

read -p 'Build region [us-east-1]: ' region
region=${region:-"us-east-1"}

read -p 'Build account number: ' build_account

root_account_arns="arn:aws:iam::${build_account}:root"

echo 'Enter information about your deploy account numbers. Leave account number blank when complete.'

deploy_accounts=()
deploy_regions=()
deploy_profiles=()

for (( ; ; ))
do
    read -p 'Account number: ' deploy_account_number
    if [ "${deploy_account_number}" == "" ]
    then
        break
    fi

    read -p 'Region: ' deploy_region
    read -p 'Profile: ' deploy_profile
    read -p 'Name (e.g. Development, Testing, Production): ' deploy_name
    echo ""

    parameter_name="/CrossAccountPipeline/${deploy_name}Account"
    parameter_description="The AccountId of the ${deploy_name} account for cross account pipelines."
    aws ssm put-parameter --profile $profile --region $region --name $parameter_name --value $deploy_account_number --type "String" --no-overwrite --description "$parameter_description"

    root_account_arns="${root_account_arns},arn:aws:iam::${deploy_account_number}:root"
    deploy_accounts+=( "${deploy_account_number}" )
    deploy_regions+=( "${deploy_region}" )
    deploy_profiles+=( "${deploy_profile}" )

done

echo $root_account_arns

primary_stack_name="CrossAccountPrimary"
deploy_stack_name="CrossAccountDeploy"
regional_stack_name="CrossAccountRegional"

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

# Get the CMK and pipeline bucket outputs
primary_region_cmk=$(echo ${stack_info} | jq -r '.Stacks[0].Outputs[] | select( .OutputKey == "CMK" ) | .OutputValue ' )
primary_pipeline_bucket=$(echo ${stack_info} | jq -r '.Stacks[0].Outputs[] | select( .OutputKey == "PipelineBucket" ) | .OutputValue ' )

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

regional_regions=()
regional_cmks=()
regional_pipeline_buckets=()

all_cmks="${primary_region_cmk}"

len=${#deploy_accounts[@]}
for (( i=0; i<$len; i++ ))
do
    deploy_region="${deploy_regions[$i]}"

    if [[ " ${regional_regions[*]} " == *"${deploy_region}"* ]]
    then
        echo "Skiping region ${deploy_region}; already created."
    else
        if [ "${deploy_region}" == "${region}" ]
        then
            echo "Skiping region ${deploy_region}; primary region."
        else
            regional_regions+=( "${deploy_region}" )
            echo "Creating regional stack in ${deploy_region}"
            aws cloudformation create-stack \
                --profile $profile \
                --region $deploy_region \
                --stack-name $regional_stack_name \
                --template-body file://CrossAccountRegional.yaml \
                --parameters \
                    ParameterKey=RootAccountArns,ParameterValue=\"$root_account_arns\" \
                    ParameterKey=PipelineBucketAccessRoleArns,ParameterValue=\"$pipeline_bucket_access_role_arns\" \
                --capabilities CAPABILITY_NAMED_IAM
        fi
    fi
done

echo 'Waiting for regional stacks to complete. This will take several minutes.'

len=${#regional_regions[@]}
for (( i=0; i<$len; i++ ))
do
    deploy_region="${regional_regions[$i]}"

    aws cloudformation wait stack-create-complete --stack-name $regional_stack_name --profile $profile --region $deploy_region

    echo "Retrieving stack info for region ${deploy_region}."
    stack_info=$(aws cloudformation describe-stacks --stack-name $regional_stack_name --profile $profile --region $deploy_region)

    # Get the CMK and pipeline bucket outputs
    regional_region_cmk=$(echo ${stack_info} | jq -r '.Stacks[0].Outputs[] | select( .OutputKey == "CMK" ) | .OutputValue ' )
    regional_cmks+=( "${regional_region_cmk}" )
    all_cmks="${all_cmks},${regional_region_cmk}"

    regional_pipeline_bucket=$(echo ${stack_info} | jq -r '.Stacks[0].Outputs[] | select( .OutputKey == "PipelineBucket" ) | .OutputValue ' )
    regional_pipeline_buckets+=( "${regional_pipeline_bucket}" )

    pipeline_bucket_star_arns="${pipeline_bucket_star_arns},arn:aws:s3:::${regional_pipeline_bucket}/*"
done

echo "Updating deployer stacks"
len=${#deploy_accounts[@]}
for (( i=0; i<$len; i++ ))
do
    echo "Updating deployer stack in account ${deploy_accounts[$i]}"

    deploy_region="${deploy_regions[$i]}"
    deploy_profile="${deploy_profiles[$i]}"
    aws cloudformation update-stack \
        --profile $deploy_profile \
        --region $deploy_region \
        --stack-name $deploy_stack_name \
        --use-previous-template \
        --parameters \
            ParameterKey=BuildAccount,UsePreviousValue=true \
            ParameterKey=CMKARNs,ParameterValue=\"$all_cmks\" \
        --capabilities CAPABILITY_NAMED_IAM
done


echo 'Waiting for deployer stacks to complete. This may take several minutes.'
len=${#deploy_accounts[@]}
for (( i=0; i<$len; i++ ))
do
    aws cloudformation wait stack-update-complete --stack-name $deploy_stack_name --profile $deploy_profile --region $deploy_region
done


echo "Updating primary stack"
aws cloudformation update-stack \
    --profile $profile \
    --region $region \
    --stack-name $primary_stack_name \
    --use-previous-template \
    --parameters \
        ParameterKey=RootAccountArns,UsePreviousValue=true \
        ParameterKey=DeployReady,UsePreviousValue=true \
        ParameterKey=PipelineBucketAccessRoleArns,UsePreviousValue=true \
        ParameterKey=PipelineBucketStarArns,ParameterValue=\"$pipeline_bucket_star_arns\" \
        ParameterKey=PipelineCMKs,ParameterValue=\"$all_cmks\" \
    --capabilities CAPABILITY_NAMED_IAM

echo "Waiting for primary stack update to complete. This will take several minutes."
aws cloudformation wait stack-update-complete --stack-name $primary_stack_name --profile $profile --region $region
