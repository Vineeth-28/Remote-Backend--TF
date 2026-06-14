# 🏗️ Terraform Remote Backend with AWS S3 + DynamoDB

> A production-grade Terraform setup using AWS S3 for remote state storage and DynamoDB for state locking — the industry standard for team-based infrastructure management.

---

## 📋 Table of Contents

- [What is a Remote Backend?](#-what-is-a-remote-backend)
- [Architecture](#-architecture)
- [Why This Setup?](#-why-this-setup)
- [Prerequisites](#-prerequisites)
- [Project Structure](#-project-structure)
- [Setup Guide](#-setup-guide)
- [File Breakdown](#-file-breakdown)
- [Common Errors & Fixes](#-common-errors--fixes)
- [Terraform Commands](#-terraform-commands)
- [How State Locking Works](#-how-state-locking-works)
- [Best Practices](#-best-practices)
- [Cost](#-cost)

---

## 🤔 What is a Remote Backend?

By default, Terraform saves your infrastructure state in a local file called `terraform.tfstate` on your computer.

**The problem with local state:**

```
❌ Only you can access it
❌ Gets lost if your laptop breaks
❌ Two people can't work together
❌ No history or versioning
❌ No locking — conflicts happen
```

**Remote backend solves all of this:**

```
✅ State stored in S3 (cloud) — accessible by the whole team
✅ DynamoDB prevents two people from applying at the same time
✅ S3 versioning keeps full history of every state change
✅ Encrypted at rest — secure
✅ Industry standard — every company uses this
```

---

## 🏛️ Architecture

```
  Developer 1 (Mumbai)          Developer 2 (USA)
        │                              │
        └──────────┐    ┌─────────────┘
                   ▼    ▼
           ┌─────────────────┐
           │    DynamoDB     │   ← Step 2: Lock state
           │ terraform-locks │     "Dev1 is running,
           └────────┬────────┘      please wait Dev2"
                    │
                    ▼
           ┌─────────────────┐
           │    S3 Bucket    │   ← Step 3: Save state
           │ terraform.tfstate│    + release lock ✅
           └────────┬────────┘
                    │
                    ▼
         ┌──────────────────────┐
         │   AWS Infrastructure │
         │  EC2 · SG · Key Pair │
         └──────────────────────┘
```

**Flow:**
1. Developer runs `terraform apply`
2. Terraform checks DynamoDB — if free, it **locks** the state
3. Changes are made on AWS
4. Updated state is **saved to S3**
5. Lock is **released** from DynamoDB ✅

---

## 💡 Why This Setup?

| Feature | Local State | Remote Backend (This Setup) |
|---|---|---|
| Team access | ❌ One person only | ✅ Whole team |
| State history | ❌ No versioning | ✅ S3 versioning |
| Conflict protection | ❌ No locking | ✅ DynamoDB locking |
| Data safety | ❌ Lost if laptop dies | ✅ Always in cloud |
| Encryption | ❌ Plain text | ✅ Encrypted at rest |
| Industry standard | ❌ | ✅ Used by every company |

---

## ✅ Prerequisites

Before starting, make sure you have:

| Tool | Version | Install |
|---|---|---|
| Terraform | >= 1.0.0 | [terraform.io](https://www.terraform.io/downloads) |
| AWS CLI | >= 2.0 | [aws.amazon.com/cli](https://aws.amazon.com/cli/) |
| AWS Account | - | [aws.amazon.com](https://aws.amazon.com) |
| IAM User with permissions | - | See below |

### IAM Permissions Required

Your AWS user needs these permissions:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:*",
        "dynamodb:*",
        "ec2:*",
        "iam:*"
      ],
      "Resource": "*"
    }
  ]
}
```

### Configure AWS CLI

```bash
aws configure
```

```
AWS Access Key ID:     → your-access-key
AWS Secret Access Key: → your-secret-key
Default region:        → us-west-2
Default output format: → json
```

Verify it works:

```bash
aws sts get-caller-identity
```

---

## 📁 Project Structure

```
REMOTE_BACKEND/
│
├── terraform.tf          # Backend config + required providers
├── provider.tf           # AWS provider + region
├── ec2.tf                # EC2, Security Group, Key Pair, Outputs
└── README.md             # This file
```

---

## 🚀 Setup Guide

### Step 1 — Create the S3 Bucket

> ⚠️ S3 bucket names are **globally unique**. Use your account ID to avoid conflicts.

```bash
aws s3api create-bucket \
  --bucket demo-state-YOUR_ACCOUNT_ID-us-west-2 \
  --region us-west-2 \
  --create-bucket-configuration LocationConstraint=us-west-2
```

Enable versioning (keeps history of every state change):

```bash
aws s3api put-bucket-versioning \
  --bucket demo-state-YOUR_ACCOUNT_ID-us-west-2 \
  --versioning-configuration Status=Enabled
```

Enable encryption (security best practice):

```bash
aws s3api put-bucket-encryption \
  --bucket demo-state-YOUR_ACCOUNT_ID-us-west-2 \
  --server-side-encryption-configuration '{
    "Rules": [{
      "ApplyServerSideEncryptionByDefault": {
        "SSEAlgorithm": "AES256"
      }
    }]
  }'
```

Block public access:

```bash
aws s3api put-public-access-block \
  --bucket demo-state-YOUR_ACCOUNT_ID-us-west-2 \
  --public-access-block-configuration \
    "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"
```

### Step 2 — Create the DynamoDB Table

```bash
aws dynamodb create-table \
  --table-name terraform-locks \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region us-west-2
```

Verify it's active:

```bash
aws dynamodb describe-table \
  --table-name terraform-locks \
  --region us-west-2 \
  --query "Table.TableStatus"
```

Expected output: `"ACTIVE"`

### Step 3 — Update terraform.tf

Replace `YOUR_ACCOUNT_ID` with your actual AWS account ID:

```hcl
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.50.0"
    }
  }

  backend "s3" {
    bucket         = "demo-state-YOUR_ACCOUNT_ID-us-west-2"
    key            = "terraform.tfstate"
    region         = "us-west-2"
    encrypt        = true
    dynamodb_table = "terraform-locks"
  }
}
```

### Step 4 — Generate SSH Key Pair

```bash
ssh-keygen -t rsa -b 4096 -f ~/.ssh/terraform_key
```

### Step 5 — Run Terraform

```bash
# Initialize — connects to S3 backend
terraform init

# Validate your code
terraform validate

# Preview what will be created
terraform plan

# Create the infrastructure
terraform apply
```

Type `yes` when prompted.

### Step 6 — Verify State is Saved in S3

```bash
aws s3 ls s3://demo-state-YOUR_ACCOUNT_ID-us-west-2/
```

You should see:

```
2026-06-14  terraform.tfstate
```

---

## 📄 File Breakdown

### `terraform.tf` — Backend + Providers

```hcl
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.50.0"
    }
  }

  backend "s3" {
    bucket         = "demo-state-943818144398-us-west-2"
    key            = "terraform.tfstate"   # path inside the bucket
    region         = "us-west-2"
    encrypt        = true                  # encrypt the state file
    dynamodb_table = "terraform-locks"     # table for locking
  }
}
```

### `provider.tf` — AWS Region

```hcl
provider "aws" {
  region = "us-west-2"
}
```

### `ec2.tf` — Infrastructure Resources

```hcl
# SSH Key Pair
resource "aws_key_pair" "deployer" {
  key_name   = "deployer-key"
  public_key = file("~/.ssh/terraform_key.pub")
}

# Security Group — allows SSH (22) and HTTP (80)
resource "aws_security_group" "web_sg" {
  name = "terraform-ssg"

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# EC2 Instance
resource "aws_instance" "web" {
  ami                    = "ami-09113138d0f0d41ff90"
  instance_type          = "t3.micro"
  vpc_security_group_ids = [aws_security_group.web_sg.id]
  key_name               = aws_key_pair.deployer.key_name

  root_block_device {
    volume_size           = 20
    volume_type           = "gp2"
    delete_on_termination = true
  }

  tags = {
    Name = "terraform-ec2"
  }
}

# Output the public IP after apply
output "public_ip" {
  value = aws_instance.web.public_ip
}
```

---

## 🔧 Common Errors & Fixes

### `BucketAlreadyExists`

```
Error: BucketAlreadyExists
```

**Cause:** Someone else already owns that bucket name globally.

**Fix:** Add your account ID to make it unique:

```bash
--bucket demo-state-YOUR_ACCOUNT_ID-us-west-2
```

---

### `403 Forbidden` on S3

```
Error: operation error S3: HeadObject, StatusCode: 403, Forbidden
```

**Cause:** Your IAM user doesn't have S3 permissions.

**Fix:**

```bash
aws iam put-user-policy \
  --user-name YOUR_USERNAME \
  --policy-name TerraformS3Access \
  --policy-document '{
    "Version": "2012-10-17",
    "Statement": [{
      "Effect": "Allow",
      "Action": ["s3:*"],
      "Resource": ["arn:aws:s3:::YOUR_BUCKET", "arn:aws:s3:::YOUR_BUCKET/*"]
    }]
  }'
```

---

### `AccessDeniedException` on DynamoDB

```
Error: AccessDeniedException: user is not authorized to perform: dynamodb:CreateTable
```

**Cause:** IAM user missing DynamoDB permissions.

**Fix:**

```bash
aws iam put-user-policy \
  --user-name YOUR_USERNAME \
  --policy-name TerraformDynamoDBAccess \
  --policy-document '{
    "Version": "2012-10-17",
    "Statement": [{
      "Effect": "Allow",
      "Action": ["dynamodb:*"],
      "Resource": "*"
    }]
  }'
```

---

### `NoSuchBucket`

```
Error: S3 bucket "demo-state" does not exist
```

**Cause:** Bucket was never created, or wrong name in `terraform.tf`.

**Fix:** Create the bucket first (Step 1), then make sure the name in `terraform.tf` matches exactly.

---

### Wrong Region in Console

**Symptom:** DynamoDB table not visible in AWS Console.

**Fix:** Check the top-right of the AWS Console — switch to `us-west-2 (Oregon)`.

---

## 🖥️ Terraform Commands

```bash
# Initialize backend (run first, and after any backend change)
terraform init

# Validate configuration files
terraform validate

# Preview changes — nothing is created
terraform plan

# Apply changes — creates real AWS resources
terraform apply

# Destroy all resources — saves money when done
terraform destroy

# Show current state
terraform show

# List all resources in state
terraform state list

# Remove old backend cache and reinitialize
rm -rf .terraform && terraform init
```

---

## 🔒 How State Locking Works

When you run `terraform apply`, here is exactly what happens:

```
1. terraform apply
        │
        ▼
2. Check DynamoDB table
        │
        ├── 🔴 LOCKED?
        │     "Error: state is locked by another user"
        │     → Wait and try again
        │
        └── 🟢 FREE?
              │
              ▼
3. Write lock to DynamoDB
   LockID = "demo-state-account/terraform.tfstate"
              │
              ▼
4. Make changes on AWS
   (create EC2, SG, Key Pair...)
              │
              ▼
5. Save new state to S3
   s3://bucket/terraform.tfstate
              │
              ▼
6. Delete lock from DynamoDB ✅
   "Lock released — others can apply now"
```

If Terraform crashes mid-apply, the lock stays in DynamoDB. You can force-unlock it:

```bash
terraform force-unlock LOCK_ID
```

---

## ✅ Best Practices

| Practice | Why |
|---|---|
| Never commit `terraform.tfstate` to Git | Contains sensitive data (IPs, passwords) |
| Add `*.tfstate` to `.gitignore` | Prevent accidental commits |
| Enable S3 versioning | Roll back to any previous state |
| Enable S3 encryption | Protect sensitive infrastructure data |
| Use DynamoDB locking | Prevent state corruption in teams |
| Use unique bucket names | Avoid `BucketAlreadyExists` errors |
| Never delete the S3 bucket | You will lose all state history |
| Run `terraform plan` before `apply` | Always preview changes first |

### Recommended `.gitignore`

```gitignore
# Terraform state files
*.tfstate
*.tfstate.backup
.terraform/
.terraform.lock.hcl
crash.log
*.tfvars
```

---

## 💰 Cost

This setup is nearly **free** for learning/demo use:

| Resource | Cost |
|---|---|
| S3 bucket (state file ~1KB) | ~$0.00/month |
| DynamoDB (PAY_PER_REQUEST, rarely used) | ~$0.00/month |
| EC2 t3.micro | ~$0.0104/hour (~$7.50/month) |

> 💡 **Tip:** Run `terraform destroy` when done to avoid EC2 charges.


## 📚 Resources

- [Terraform S3 Backend Docs](https://developer.hashicorp.com/terraform/language/backend/s3)
- [AWS S3 Documentation](https://docs.aws.amazon.com/s3/)
- [AWS DynamoDB Documentation](https://docs.aws.amazon.com/dynamodb/)
- [Terraform Best Practices](https://developer.hashicorp.com/terraform/language)