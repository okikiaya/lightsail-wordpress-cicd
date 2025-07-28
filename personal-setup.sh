#!/bin/bash

# Personal AWS Account Setup - 875549173295
ACCOUNT_ID="875549173295"
REGION="eu-west-2"
INSTANCE_NAME="my-wordpress-instance"
BUCKET_NAME="lightsail-wordpress-pipeline-875549173295"

echo "Setting up CI/CD for AWS Account: $ACCOUNT_ID"

# Step 1: Create IAM User
echo "Creating IAM user..."
aws iam create-user --user-name LightSailCodeDeployUser

aws iam put-user-policy --user-name LightSailCodeDeployUser --policy-name CodeDeployOnPremisesPolicy --policy-document '{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "codedeploy:*"
      ],
      "Resource": "*"
    }
  ]
}'

echo "Creating access keys (SAVE THESE!):"
aws iam create-access-key --user-name LightSailCodeDeployUser

# Step 2: Create CodeDeploy Service Role
echo "Creating CodeDeploy service role..."
cat > codedeploy-trust-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "codedeploy.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF

aws iam create-role \
    --role-name CodeDeployServiceRole \
    --assume-role-policy-document file://codedeploy-trust-policy.json

aws iam attach-role-policy \
    --role-name CodeDeployServiceRole \
    --policy-arn arn:aws:iam::aws:policy/service-role/AWSCodeDeployRole

# Step 3: Create CodePipeline Service Role
echo "Creating CodePipeline service role..."
cat > codepipeline-trust-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "codepipeline.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF

aws iam create-role \
    --role-name CodePipelineServiceRole \
    --assume-role-policy-document file://codepipeline-trust-policy.json

aws iam attach-role-policy \
    --role-name CodePipelineServiceRole \
    --policy-arn arn:aws:iam::aws:policy/AWSCodePipelineServiceRole

aws iam attach-role-policy \
    --role-name CodePipelineServiceRole \
    --policy-arn arn:aws:iam::aws:policy/AmazonS3FullAccess

aws iam attach-role-policy \
    --role-name CodePipelineServiceRole \
    --policy-arn arn:aws:iam::aws:policy/AWSCodeDeployFullAccess

# Step 4: Create S3 bucket
echo "Creating S3 bucket..."
aws s3 mb s3://$BUCKET_NAME --region $REGION

# Step 5: Create CodeDeploy application
echo "Creating CodeDeploy application..."
aws deploy create-application \
    --application-name lightsail-wordpress-app \
    --compute-platform Server \
    --region $REGION

echo ""
echo "Setup complete! Next steps:"
echo "1. Create a Lightsail instance"
echo "2. Install CodeDeploy agent on the instance using the credentials above"
echo "3. Register the instance with CodeDeploy"
echo "4. Store your GitHub token in Systems Manager"
echo "5. Update pipeline-config.json with your GitHub details"
echo "6. Create the pipeline"

# Cleanup
rm -f codedeploy-trust-policy.json codepipeline-trust-policy.json