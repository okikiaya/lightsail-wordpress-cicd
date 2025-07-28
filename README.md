# CI/CD Pipeline: GitHub to Amazon Lightsail for WordPress

This guide sets up an automated CI/CD pipeline that deploys WordPress from GitHub to Amazon Lightsail using AWS CodePipeline and CodeDeploy.

## Prerequisites

- AWS Account with appropriate permissions
- Amazon Lightsail instance running Amazon Linux 2
- GitHub repository
- AWS CLI installed and configured

## Architecture

GitHub → CodePipeline → CodeDeploy → Lightsail Instance

## Step 1: Create IAM User for Lightsail

```bash
# Create IAM user
aws iam create-user --user-name LightSailCodeDeployUser

# Create policy
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

# Create access keys (save the output)
aws iam create-access-key --user-name LightSailCodeDeployUser
```

## Step 2: Install CodeDeploy Agent on Lightsail

SSH into your Lightsail instance and run:

```bash
# Update system and install dependencies
sudo yum update -y
sudo yum install ruby -y

# Create configuration directory
sudo mkdir -p /etc/codedeploy-agent/conf

# Create configuration file (replace with your actual credentials)
sudo sh -c 'echo "---
aws_access_key_id: YOUR_ACCESS_KEY_ID
aws_secret_access_key: YOUR_SECRET_ACCESS_KEY
iam_user_arn: arn:aws:iam::YOUR_ACCOUNT_ID:user/LightSailCodeDeployUser
region: YOUR_REGION" > /etc/codedeploy-agent/conf/codedeploy.onpremises.yml'

# Set permissions
sudo chmod 600 /etc/codedeploy-agent/conf/codedeploy.onpremises.yml
sudo chown root:root /etc/codedeploy-agent/conf/codedeploy.onpremises.yml

# Download and install CodeDeploy agent
cd /home/ec2-user
wget https://aws-codedeploy-YOUR_REGION.s3.YOUR_REGION.amazonaws.com/latest/install
chmod +x ./install
sudo ./install auto

# Start and enable service
sudo service codedeploy-agent start
sudo chkconfig codedeploy-agent on
```

## Step 3: Register Lightsail Instance

```bash
# Register instance
aws deploy register-on-premises-instance \
    --instance-name YOUR_INSTANCE_NAME \
    --iam-user-arn arn:aws:iam::YOUR_ACCOUNT_ID:user/LightSailCodeDeployUser \
    --region YOUR_REGION

# Add tags
aws deploy add-tags-to-on-premises-instances \
    --instance-names YOUR_INSTANCE_NAME \
    --tags Key=Name,Value=LightsailDemo Key=Environment,Value=Production \
    --region YOUR_REGION
```

## Step 4: Create CodeDeploy Service Role

```bash
# Create trust policy
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

# Create role
aws iam create-role \
    --role-name CodeDeployServiceRole \
    --assume-role-policy-document file://codedeploy-trust-policy.json

# Attach policy
aws iam attach-role-policy \
    --role-name CodeDeployServiceRole \
    --policy-arn arn:aws:iam::aws:policy/service-role/AWSCodeDeployRole
```

## Step 5: Create CodeDeploy Application

```bash
# Create application
aws deploy create-application \
    --application-name lightsail-wordpress-app \
    --compute-platform Server \
    --region YOUR_REGION

# Create deployment group
aws deploy create-deployment-group \
    --application-name lightsail-wordpress-app \
    --deployment-group-name lightsail-deployment-group \
    --service-role-arn arn:aws:iam::YOUR_ACCOUNT_ID:role/CodeDeployServiceRole \
    --on-premises-instance-tag-filters Key=Name,Value=LightsailDemo,Type=KEY_AND_VALUE \
    --region YOUR_REGION
```

## Step 6: Create CodePipeline Service Role

```bash
# Create trust policy
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

# Create role
aws iam create-role \
    --role-name CodePipelineServiceRole \
    --assume-role-policy-document file://codepipeline-trust-policy.json

# Attach policies
aws iam attach-role-policy \
    --role-name CodePipelineServiceRole \
    --policy-arn arn:aws:iam::aws:policy/AWSCodePipelineServiceRole

aws iam attach-role-policy \
    --role-name CodePipelineServiceRole \
    --policy-arn arn:aws:iam::aws:policy/AmazonS3FullAccess

aws iam attach-role-policy \
    --role-name CodePipelineServiceRole \
    --policy-arn arn:aws:iam::aws:policy/AWSCodeDeployFullAccess
```

## Step 7: Setup GitHub Integration

```bash
# Store GitHub personal access token
aws ssm put-parameter \
    --name "/github/personal-access-token" \
    --value "YOUR_GITHUB_TOKEN" \
    --type "SecureString"

# Create S3 bucket for artifacts
aws s3 mb s3://YOUR_PIPELINE_ARTIFACTS_BUCKET --region YOUR_REGION
```

## Step 8: Create CodePipeline

Create `pipeline-config.json`:

```json
{
  "pipeline": {
    "name": "lightsail-cicd-pipeline",
    "roleArn": "arn:aws:iam::YOUR_ACCOUNT_ID:role/CodePipelineServiceRole",
    "artifactStore": {
      "type": "S3",
      "location": "YOUR_PIPELINE_ARTIFACTS_BUCKET"
    },
    "stages": [
      {
        "name": "Source",
        "actions": [
          {
            "name": "SourceAction",
            "actionTypeId": {
              "category": "Source",
              "owner": "ThirdParty",
              "provider": "GitHub",
              "version": "1"
            },
            "configuration": {
              "Owner": "YOUR_GITHUB_USERNAME",
              "Repo": "YOUR_REPO_NAME",
              "Branch": "main",
              "OAuthToken": "{{resolve:ssm:/github/personal-access-token}}"
            },
            "outputArtifacts": [
              {
                "name": "SourceOutput"
              }
            ]
          }
        ]
      },
      {
        "name": "Deploy",
        "actions": [
          {
            "name": "DeployAction",
            "actionTypeId": {
              "category": "Deploy",
              "owner": "AWS",
              "provider": "CodeDeploy",
              "version": "1"
            },
            "configuration": {
              "ApplicationName": "lightsail-wordpress-app",
              "DeploymentGroupName": "lightsail-deployment-group"
            },
            "inputArtifacts": [
              {
                "name": "SourceOutput"
              }
            ]
          }
        ]
      }
    ]
  }
}
```

Create pipeline:
```bash
aws codepipeline create-pipeline --cli-input-json file://pipeline-config.json
```

## Step 9: Add Deployment Files to GitHub Repository

### appspec.yml
```yaml
version: 0.0
os: linux
files:
  - source: /
    destination: /var/www/html
    overwrite: yes
permissions:
  - object: /var/www/html
    owner: apache
    group: apache
    mode: 755
    type:
      - file
      - directory
hooks:
  BeforeInstall:
    - location: scripts/install_dependencies.sh
      timeout: 300
      runas: root
  AfterInstall:
    - location: scripts/setup_wordpress.sh
      timeout: 600
      runas: root
  ApplicationStart:
    - location: scripts/start_server.sh
      timeout: 300
      runas: root
  ApplicationStop:
    - location: scripts/stop_server.sh
      timeout: 300
      runas: root
  ValidateService:
    - location: scripts/validate_service.sh
      timeout: 300
      runas: root
```

### scripts/install_dependencies.sh
```bash
#!/bin/bash
yum update -y
yum install -y httpd php php-mysql mariadb-server
systemctl enable httpd
systemctl enable mariadb
```

### scripts/setup_wordpress.sh
```bash
#!/bin/bash
cd /tmp
wget https://wordpress.org/latest.tar.gz
tar xzf latest.tar.gz
cp -r wordpress/* /var/www/html/
chown -R apache:apache /var/www/html/
chmod -R 755 /var/www/html/

cp /var/www/html/wp-config-sample.php /var/www/html/wp-config.php

mysql -e "CREATE DATABASE IF NOT EXISTS wordpress;"
mysql -e "CREATE USER IF NOT EXISTS 'wpuser'@'localhost' IDENTIFIED BY 'wppassword';"
mysql -e "GRANT ALL PRIVILEGES ON wordpress.* TO 'wpuser'@'localhost';"
mysql -e "FLUSH PRIVILEGES;"
```

### scripts/start_server.sh
```bash
#!/bin/bash
systemctl start mariadb
systemctl start httpd
```

### scripts/stop_server.sh
```bash
#!/bin/bash
systemctl stop httpd
systemctl stop mariadb
```

### scripts/validate_service.sh
```bash
#!/bin/bash
curl -f http://localhost/ || exit 1
```

### wp-config.php
```php
<?php
define( 'DB_NAME', 'wordpress' );
define( 'DB_USER', 'wpuser' );
define( 'DB_PASSWORD', 'wppassword' );
define( 'DB_HOST', 'localhost' );
define( 'DB_CHARSET', 'utf8' );
define( 'DB_COLLATE', '' );

define( 'AUTH_KEY',         'put your unique phrase here' );
define( 'SECURE_AUTH_KEY',  'put your unique phrase here' );
define( 'LOGGED_IN_KEY',    'put your unique phrase here' );
define( 'NONCE_KEY',        'put your unique phrase here' );
define( 'AUTH_SALT',        'put your unique phrase here' );
define( 'SECURE_AUTH_SALT', 'put your unique phrase here' );
define( 'LOGGED_IN_SALT',   'put your unique phrase here' );
define( 'NONCE_SALT',       'put your unique phrase here' );

$table_prefix = 'wp_';
define( 'WP_DEBUG', false );

if ( ! defined( 'ABSPATH' ) ) {
    define( 'ABSPATH', __DIR__ . '/' );
}

require_once ABSPATH . 'wp-settings.php';
?>
```

### index.php
```php
<?php
define( 'WP_USE_THEMES', true );
require __DIR__ . '/wp-blog-header.php';
?>
```

## Step 10: Test the Pipeline

1. Commit and push files to your GitHub repository
2. Monitor pipeline execution in AWS CodePipeline console
3. Check deployment status in AWS CodeDeploy console
4. Access your WordPress site at your Lightsail instance IP

## Troubleshooting

- **CodeDeploy agent logs**: `/var/log/aws/codedeploy-agent/`
- **Pipeline failures**: Check CloudWatch logs
- **Service status**: `sudo service codedeploy-agent status`

## Security Notes

- Rotate IAM access keys regularly
- Use least privilege IAM policies
- Enable CloudTrail for audit logging
- Consider using VPC endpoints for private communication

## Cleanup

To remove resources:
```bash
aws codepipeline delete-pipeline --name lightsail-cicd-pipeline
aws deploy delete-deployment-group --application-name lightsail-wordpress-app --deployment-group-name lightsail-deployment-group
aws deploy delete-application --application-name lightsail-wordpress-app
aws iam delete-role --role-name CodePipelineServiceRole
aws iam delete-role --role-name CodeDeployServiceRole
aws iam delete-user --user-name LightSailCodeDeployUser
```