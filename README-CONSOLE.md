# CI/CD Pipeline: GitHub to Amazon Lightsail for WordPress (AWS Console Guide)

This guide sets up an automated CI/CD pipeline using the AWS Console to deploy WordPress from GitHub to Amazon Lightsail.

## Prerequisites

- AWS Account with console access
- Amazon Lightsail instance running Amazon Linux 2
- GitHub repository
- GitHub Personal Access Token

## Architecture

GitHub → CodePipeline → CodeDeploy → Lightsail Instance

## Step 1: Create IAM User for Lightsail

### 1.1 Create IAM User
1. Go to **IAM Console** → **Users** → **Create user**
2. Username: `LightSailCodeDeployUser`
3. Select **Programmatic access**
4. Click **Next**

### 1.2 Attach Permissions
1. Select **Attach policies directly**
2. Create custom policy:
   - Click **Create policy**
   - Select **JSON** tab
   - Paste this policy:
```json
{
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
}
```
3. Name: `CodeDeployOnPremisesPolicy`
4. Create policy and attach to user

### 1.3 Create Access Keys
1. Go to user → **Security credentials** tab
2. Click **Create access key**
3. Select **Other** → **Create access key**
4. **Save the Access Key ID and Secret Access Key** (you'll need these later)

## Step 2: Create Service Roles

### 2.1 Create CodeDeploy Service Role
1. Go to **IAM Console** → **Roles** → **Create role**
2. Select **AWS service** → **CodeDeploy**
3. Select **CodeDeploy** use case
4. Attach policy: `AWSCodeDeployRole`
5. Role name: `CodeDeployServiceRole`
6. Create role

### 2.2 Create CodePipeline Policy (First)
1. Go to **IAM Console** → **Policies** → **Create policy**
2. Select **JSON** tab
3. Paste this policy:
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetBucketVersioning",
        "s3:GetObject",
        "s3:GetObjectVersion",
        "s3:PutObject",
        "s3:ListBucket"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "codedeploy:CreateDeployment",
        "codedeploy:GetApplication",
        "codedeploy:GetApplicationRevision",
        "codedeploy:GetDeployment",
        "codedeploy:GetDeploymentConfig",
        "codedeploy:RegisterApplicationRevision"
      ],
      "Resource": "*"
    }
  ]
}
```
4. Name: `CodePipelineCustomPolicy`
5. Create policy

### 2.3 Create CodePipeline Service Role
1. Go to **IAM Console** → **Roles** → **Create role**
2. Select **Custom trust policy**
3. Paste this trust policy:
```json
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
```
4. Click **Next**
5. Attach these policies:
   - `CodePipelineCustomPolicy` (the one you just created)
   - `AmazonS3FullAccess`
   - `AWSCodeDeployFullAccess`
6. Role name: `CodePipelineServiceRole`
7. Create role

## Step 3: Set Up Lightsail Instance

### 3.1 Create Lightsail Instance
1. Go to **Lightsail Console**
2. Click **Create instance**
3. Select **Linux/Unix** → **Amazon Linux 2**
4. Choose instance plan
5. Name: `wordpress-cicd-instance`
6. Create instance

### 3.2 Install CodeDeploy Agent
1. Connect to instance via SSH (use browser-based SSH)
2. Run these commands:

```bash
# Update system
sudo yum update -y
sudo yum install ruby -y

# Create config directory
sudo mkdir -p /etc/codedeploy-agent/conf

# Create config file (replace with your actual values)
sudo sh -c 'echo "---
aws_access_key_id: YOUR_ACCESS_KEY_ID
aws_secret_access_key: YOUR_SECRET_ACCESS_KEY
iam_user_arn: arn:aws:iam::YOUR_ACCOUNT_ID:user/LightSailCodeDeployUser
region: eu-west-2" > /etc/codedeploy-agent/conf/codedeploy.onpremises.yml'

# Set permissions
sudo chmod 600 /etc/codedeploy-agent/conf/codedeploy.onpremises.yml
sudo chown root:root /etc/codedeploy-agent/conf/codedeploy.onpremises.yml

# Install CodeDeploy agent
cd /home/ec2-user
wget https://aws-codedeploy-eu-west-2.s3.eu-west-2.amazonaws.com/latest/install
chmod +x ./install
sudo ./install auto

# Start service
sudo service codedeploy-agent start
sudo chkconfig codedeploy-agent on
```

## Step 4: Register Lightsail Instance with CodeDeploy

### 4.1 Using AWS CloudShell
1. Go to **AWS Console** → Click **CloudShell** icon (top right)
2. Run these commands:

```bash
# Register instance
aws deploy register-on-premises-instance \
    --instance-name wordpress-cicd-instance \
    --iam-user-arn arn:aws:iam::YOUR_ACCOUNT_ID:user/LightSailCodeDeployUser \
    --region eu-west-2

# Add tags
aws deploy add-tags-to-on-premises-instances \
    --instance-names wordpress-cicd-instance \
    --tags Key=Name,Value=LightsailDemo Key=Environment,Value=Production \
    --region eu-west-2
```

## Step 5: Create CodeDeploy Application

### 5.1 Create Application
1. Go to **CodeDeploy Console** → **Applications** → **Create application**
2. Application name: `lightsail-wordpress-app`
3. Compute platform: **EC2/On-premises**
4. Create application

### 5.2 Create Deployment Group
1. In the application → **Create deployment group**
2. Deployment group name: `lightsail-deployment-group`
3. Service role: `arn:aws:iam::YOUR_ACCOUNT_ID:role/CodeDeployServiceRole`
4. Deployment type: **In-place**
5. Environment configuration: **On-premises instances**
6. Key: `Name`, Value: `LightsailDemo`
7. Create deployment group

## Step 6: Store GitHub Token

### 6.1 Create GitHub Personal Access Token
1. Go to **GitHub** → **Settings** → **Developer settings** → **Personal access tokens**
2. Generate new token with `repo` permissions
3. Copy the token

### 6.2 Store in AWS Systems Manager
1. Go to **Systems Manager Console** → **Parameter Store** → **Create parameter**
2. Name: `/github/personal-access-token`
3. Type: **SecureString**
4. Value: [Your GitHub token]
5. Create parameter

## Step 7: Create S3 Bucket for Artifacts

1. Go to **S3 Console** → **Create bucket**
2. Bucket name: `lightsail-wordpress-pipeline-YOUR_ACCOUNT_ID`
3. Region: **eu-west-2**
4. Keep default settings
5. Create bucket

## Step 8: Create CodePipeline

### 8.1 Create Pipeline
1. Go to **CodePipeline Console** → **Create pipeline**
2. Pipeline name: `lightsail-cicd-pipeline`
3. Service role: **New service role** (or select existing `CodePipelineServiceRole`)
4. Artifact store: **Default location** or select your S3 bucket
5. Click **Next**

### 8.2 Add Source Stage
1. Source provider: **GitHub (Version 1)**
2. Connect to GitHub (authorize if needed)
3. Repository: Select your repository
4. Branch: `main` or `master`
5. Click **Next**

### 8.3 Skip Build Stage
1. Click **Skip build stage**
2. Confirm skip

### 8.4 Add Deploy Stage
1. Deploy provider: **AWS CodeDeploy**
2. Region: **eu-west-2**
3. Application name: `lightsail-wordpress-app`
4. Deployment group: `lightsail-deployment-group`
5. Click **Next**

### 8.5 Review and Create
1. Review settings
2. Click **Create pipeline**

## Step 9: Prepare GitHub Repository

### 9.1 Add Required Files
Add these files to your GitHub repository root:

**appspec.yml**
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

### 9.2 Create Scripts Folder
Create a `scripts/` folder with these files:

**scripts/install_dependencies.sh**
```bash
#!/bin/bash
yum update -y
yum install -y httpd php php-mysql mariadb-server
systemctl enable httpd
systemctl enable mariadb
```

**scripts/setup_wordpress.sh**
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

**scripts/start_server.sh**
```bash
#!/bin/bash
systemctl start mariadb
systemctl start httpd
```

**scripts/stop_server.sh**
```bash
#!/bin/bash
systemctl stop httpd
systemctl stop mariadb
```

**scripts/validate_service.sh**
```bash
#!/bin/bash
curl -f http://localhost/ || exit 1
```

### 9.3 Add WordPress Files

**wp-config.php**
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

**index.php**
```php
<?php
define( 'WP_USE_THEMES', true );
require __DIR__ . '/wp-blog-header.php';
?>
```

## Step 10: Test the Pipeline

1. **Commit and push** all files to your GitHub repository
2. Go to **CodePipeline Console** → Your pipeline
3. Watch the pipeline execute automatically
4. Check **CodeDeploy Console** for deployment status
5. Access your WordPress site at your Lightsail instance's public IP

## Step 11: Configure WordPress

1. Open browser to your Lightsail instance IP
2. Complete WordPress installation wizard
3. Create admin account
4. Your WordPress site is now live!

## Monitoring and Troubleshooting

### Pipeline Monitoring
- **CodePipeline Console**: View pipeline execution status
- **CodeDeploy Console**: View deployment details and logs
- **CloudWatch Logs**: View detailed execution logs

### Common Issues
- **CodeDeploy agent not running**: Check service status on Lightsail instance
- **Permission errors**: Verify IAM roles and policies
- **GitHub connection issues**: Check personal access token permissions

### Lightsail Instance Logs
```bash
# CodeDeploy agent logs
sudo tail -f /var/log/aws/codedeploy-agent/codedeploy-agent.log

# Check service status
sudo service codedeploy-agent status
```

## Security Best Practices

1. **Rotate credentials** regularly
2. **Use least privilege** IAM policies
3. **Enable CloudTrail** for audit logging
4. **Secure your Lightsail instance** with proper firewall rules
5. **Use HTTPS** for production WordPress sites

## Cleanup

To remove all resources:

1. **Delete CodePipeline**: CodePipeline Console → Delete pipeline
2. **Delete CodeDeploy**: CodeDeploy Console → Delete application
3. **Delete IAM roles**: IAM Console → Delete roles
4. **Delete S3 bucket**: S3 Console → Delete bucket
5. **Delete Lightsail instance**: Lightsail Console → Delete instance

---

**Note**: Replace `YOUR_ACCOUNT_ID` with your actual AWS account ID (875549173295) throughout this guide.