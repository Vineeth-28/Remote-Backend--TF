# 🧪 Testing Terraform Remote Backend with Two Systems

> A step-by-step guide to verify your Terraform remote backend is working correctly — testing shared state, DynamoDB locking, versioning, and recovery.

---

## 📋 Table of Contents

- [What Are We Testing?](#-what-are-we-testing)
- [Test Architecture](#-test-architecture)
- [Setup System 2 (AWS CloudShell)](#-setup-system-2-aws-cloudshell)
- [Test 1 — Shared State](#test-1--shared-state)
- [Test 2 — State Locking](#test-2--state-locking)
- [Test 3 — DynamoDB Lock Record](#test-3--dynamodb-lock-record)
- [Test 4 — S3 Versioning](#test-4--s3-versioning)
- [Test 5 — Force Unlock](#test-5--force-unlock)
- [Full Test Checklist](#-full-test-checklist)
- [What Each Test Proves](#-what-each-test-proves)

---

## 🤔 What Are We Testing?

A remote backend has **4 key features** — we test each one:

| Feature | What It Does | Test |
|---|---|---|
| Shared state | Both systems see same infrastructure | `terraform state list` on both |
| State locking | Only one person can apply at a time | Apply on both simultaneously |
| Versioning | S3 keeps history of every state change | List object versions in S3 |
| Recovery | Manually release a stuck lock | `terraform force-unlock` |

---

## 🏛️ Test Architecture

```
  System 1 — Your Mac              System 2 — AWS CloudShell
  (already configured)             (browser terminal, free)
        │                                    │
        └──────────────┐    ┌────────────────┘
                       ▼    ▼
              ┌──────────────────┐
              │    DynamoDB      │
              │  terraform-locks │  ← Test 2 & 3: Lock record
              └────────┬─────────┘
                       │
                       ▼
              ┌──────────────────┐
              │    S3 Bucket     │
              │ terraform.tfstate│  ← Test 1 & 4: Shared + versioned
              └──────────────────┘
```

> 💡 You do **not** need a friend or a second computer. AWS CloudShell simulates System 2 for free inside your browser.

---

## 🖥️ Setup System 2 (AWS CloudShell)

### Step 1 — Open CloudShell

```
AWS Console → search "CloudShell" → click Open
```

> CloudShell is a free browser-based terminal with AWS credentials pre-configured. No setup needed.

### Step 2 — Install Terraform

```bash
sudo yum install -y yum-utils
sudo yum-config-manager --add-repo \
  https://rpm.releases.hashicorp.com/AmazonLinux/hashicorp.repo
sudo yum install terraform -y

# Verify installation
terraform version
```

### Step 3 — Create Project Folder

```bash
mkdir remote-backend-test && cd remote-backend-test
```

### Step 4 — Create the Same Backend Config

```bash
cat > terraform.tf << 'EOF'
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.50.0"
    }
  }

  backend "s3" {
    bucket         = "demo-state-943818144398-us-west-2"
    key            = "terraform.tfstate"
    region         = "us-west-2"
    encrypt        = true
    dynamodb_table = "terraform-locks"
  }
}
EOF
```

### Step 5 — Initialize Backend

```bash
terraform init
```

✅ Expected output:
```
Successfully configured the backend "s3"!
Terraform has been successfully initialized!
```

> Both systems now point to the **same S3 bucket and DynamoDB table**.

---

## Test 1 — Shared State

**Goal:** Prove both systems can read the same Terraform state.

### On System 1 (Your Mac):

```bash
terraform state list
```

Output:
```
aws_instance.web
aws_key_pair.deployer
aws_security_group.web_sg
```

### On System 2 (CloudShell):

```bash
terraform state list
```

Output (should be **identical** ✅):
```
aws_instance.web
aws_key_pair.deployer
aws_security_group.web_sg
```

### Also verify the state details match:

```bash
# Run on both — output must be same
terraform show
```

### ✅ Pass Condition

Both systems show the same resources. This proves:
- State is stored in S3, not locally
- Any system with correct AWS credentials can access it
- The team can collaborate on the same infrastructure

---

## Test 2 — State Locking

**Goal:** Prove DynamoDB prevents two systems from applying at the same time.

### Step 1 — Start apply on System 1 (Mac)

```bash
# On your Mac
terraform apply
```

When it asks:
```
Do you want to perform these actions?
  Enter a value:
```

**Type `yes` but keep this terminal open — do NOT let it finish yet.**

### Step 2 — Immediately try apply on System 2 (CloudShell)

```bash
# In CloudShell — run at the same time as System 1
terraform apply
```

### ✅ Expected Error on System 2:

```
╷
│ Error: Error acquiring the state lock
│
│ Error message: ConditionalCheckFailedException
│
│ Terraform acquires a state lock to protect the state from
│ being written by multiple users at the same time.
│
│   ID:        f4e3b2a1-xxxx-xxxx-xxxx-xxxxxxxxxxxx
│   Path:      demo-state-943818144398-us-west-2/terraform.tfstate
│   Operation: OperationTypeApply
│   Who:       vineet@Vineets-MacBook-Pro
│   Created:   2026-06-14 04:06:27.367 +0000 UTC
│
│ Terraform detected that another process is holding the lock.
│ Either another instance of Terraform is running, or a previous
│ run exited without releasing the lock.
╵
```

> 💡 **This error IS the success.** System 2 is correctly blocked while System 1 is running.

---

## Test 3 — DynamoDB Lock Record

**Goal:** See the lock record in DynamoDB while System 1 is applying.

### Via AWS Console (Visual)

While System 1 is still applying:

```
AWS Console
  → DynamoDB
  → Tables
  → terraform-locks
  → Explore items
```

You will see a record like this:

```json
{
  "LockID": {
    "S": "demo-state-943818144398-us-west-2/terraform.tfstate"
  },
  "Info": {
    "S": "{
      \"ID\": \"f4e3b2a1-xxxx-xxxx\",
      \"Operation\": \"OperationTypeApply\",
      \"Who\": \"vineet@Vineets-MacBook-Pro\",
      \"Version\": \"1.0.0\",
      \"Created\": \"2026-06-14T04:06:27.367Z\"
    }"
  }
}
```

### Via AWS CLI

```bash
# Check lock from any terminal
aws dynamodb scan \
  --table-name terraform-locks \
  --region us-west-2
```

Output while locked:
```json
{
  "Items": [
    {
      "LockID": { "S": "demo-state-943818144398-us-west-2/terraform.tfstate" },
      "Info":   { "S": "{ \"Who\": \"vineet@Vineets-MacBook-Pro\" ... }" }
    }
  ],
  "Count": 1
}
```

Output after apply finishes:
```json
{
  "Items": [],
  "Count": 0
}
```

> 💡 Lock record **disappears** automatically after apply completes ✅

---

## Test 4 — S3 Versioning

**Goal:** Prove S3 keeps a full history of every state change.

### Run apply twice (to create two versions):

```bash
# First apply — creates resources
terraform apply

# Make a small change (e.g. change EC2 tag), then apply again
terraform apply
```

### Check versions in S3:

```bash
aws s3api list-object-versions \
  --bucket demo-state-943818144398-us-west-2 \
  --prefix terraform.tfstate
```

✅ Expected output:
```json
{
  "Versions": [
    {
      "Key":          "terraform.tfstate",
      "VersionId":    "abc123newVersion",
      "LastModified": "2026-06-14T10:30:00",
      "Size":         2456,
      "IsLatest":     true
    },
    {
      "Key":          "terraform.tfstate",
      "VersionId":    "xyz789oldVersion",
      "LastModified": "2026-06-14T09:00:00",
      "Size":         2301,
      "IsLatest":     false
    }
  ]
}
```

### Roll back to a previous state (if needed):

```bash
# Download a specific old version
aws s3api get-object \
  --bucket demo-state-943818144398-us-west-2 \
  --key terraform.tfstate \
  --version-id xyz789oldVersion \
  terraform.tfstate.backup
```

> 💡 This is like **Git for your infrastructure** — every apply is a commit you can roll back to.

---

## Test 5 — Force Unlock

**Goal:** Learn how to release a lock that got stuck (e.g. Terraform crashed mid-apply).

### When does a stuck lock happen?

```
terraform apply is running
       │
       ▼
  Lock created in DynamoDB ← ✅
       │
       ▼
  Your internet cuts out / laptop dies / Ctrl+C
       │
       ▼
  Lock NEVER released ← ❌ stuck forever
       │
       ▼
  Next terraform apply fails:
  "Error acquiring the state lock"
```

### How to fix it:

**Option A — Using Terraform (recommended):**

```bash
# Get the lock ID from the error message, then:
terraform force-unlock LOCK_ID_HERE

# Example:
terraform force-unlock f4e3b2a1-xxxx-xxxx-xxxx-xxxxxxxxxxxx
```

Terraform will ask:
```
Do you really want to force-unlock?
  Terraform will remove the lock on the remote state.
  Enter a value: yes
```

**Option B — Delete directly from DynamoDB:**

```bash
aws dynamodb delete-item \
  --table-name terraform-locks \
  --key '{
    "LockID": {
      "S": "demo-state-943818144398-us-west-2/terraform.tfstate"
    }
  }' \
  --region us-west-2
```

### Verify lock is released:

```bash
aws dynamodb scan \
  --table-name terraform-locks \
  --region us-west-2
```

✅ Expected:
```json
{
  "Items": [],
  "Count": 0
}
```

---

## ✅ Full Test Checklist

Run through all tests and tick them off:

```
SHARED STATE
□ terraform state list on Mac shows resources
□ terraform state list on CloudShell shows SAME resources
□ terraform show output matches on both systems

STATE LOCKING
□ Apply on System 1 starts successfully
□ Apply on System 2 gets "Error acquiring the state lock"
□ Error message shows correct Who/Operation/Created fields

DYNAMODB LOCK RECORD
□ Lock record visible in DynamoDB console during apply
□ aws dynamodb scan shows Count: 1 during apply
□ Lock record disappears after apply completes (Count: 0)

S3 VERSIONING
□ aws s3api list-object-versions shows multiple versions
□ Each version has different VersionId and LastModified
□ IsLatest: true on most recent version

FORCE UNLOCK
□ terraform force-unlock successfully removes stuck lock
□ OR aws dynamodb delete-item removes lock manually
□ aws dynamodb scan shows Count: 0 after unlock
```

---

## 📊 What Each Test Proves

| Test | Proves | Why It Matters |
|---|---|---|
| **Shared state** | S3 is the single source of truth | Team can collaborate safely |
| **State locking** | DynamoDB prevents conflicts | No corrupted state files |
| **Lock record** | Lock mechanism is visible/auditable | Can debug stuck locks |
| **S3 versioning** | Full history of infrastructure changes | Can roll back after mistakes |
| **Force unlock** | Recovery from crashes | Production reliability |

---

## 🔍 Useful Debug Commands

```bash
# Check which system currently holds the lock
aws dynamodb scan \
  --table-name terraform-locks \
  --region us-west-2

# Check all state versions
aws s3api list-object-versions \
  --bucket demo-state-943818144398-us-west-2 \
  --prefix terraform.tfstate

# View current state
terraform show

# List all resources in state
terraform state list

# Inspect a specific resource in state
terraform state show aws_instance.web

# Pull latest state from S3
terraform state pull

# Check backend configuration
terraform version
```

---

## ⚠️ Common Issues During Testing

### Lock error even when no one is applying

```
Error: Error acquiring the state lock
```

**Fix:** Previous apply crashed and left lock behind:

```bash
terraform force-unlock LOCK_ID
```

---

### CloudShell loses files after session

CloudShell storage resets after inactivity.

**Fix:** Re-create the `terraform.tf` file and run `terraform init` again.

---

### System 2 shows different state

```
No changes — state is empty
```

**Fix:** Wrong bucket name in `terraform.tf` — make sure both systems use the **exact same** bucket name, key, and region.

---

### `terraform init` fails on CloudShell

```
Error: Failed to get existing workspaces
```

**Fix:** CloudShell IAM role might not have S3 access. Verify:

```bash
aws sts get-caller-identity  # check who you are
aws s3 ls                    # check S3 access
```

---

## 👤 Environment Details

| Setting | Value |
|---|---|
| AWS Account | `943818144398` |
| Region | `us-west-2 (Oregon)` |
| S3 Bucket | `demo-state-943818144398-us-west-2` |
| DynamoDB Table | `terraform-locks` |
| State Key | `terraform.tfstate` |
| System 1 | Mac (VS Code terminal) |
| System 2 | AWS CloudShell (browser) |

---

## 📚 Related Files

| File | Description |
|---|---|
| `README.md` | Main setup guide for remote backend |
| `terraform.tf` | Backend configuration |
| `provider.tf` | AWS provider and region |
| `ec2.tf` | Infrastructure resources |
| `.gitignore` | Files excluded from Git |

---

## 📚 Resources

- [Terraform S3 Backend Docs](https://developer.hashicorp.com/terraform/language/backend/s3)
- [Terraform State Locking](https://developer.hashicorp.com/terraform/language/state/locking)
- [AWS CloudShell Docs](https://docs.aws.amazon.com/cloudshell/latest/userguide/welcome.html)
- [AWS DynamoDB Docs](https://docs.aws.amazon.com/dynamodb/)
- [Terraform force-unlock](https://developer.hashicorp.com/terraform/cli/commands/force-unlock)
