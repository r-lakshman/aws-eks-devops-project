# Prerequisites – Create & Connect to Ubuntu EC2 Workstation

**Region:** `ap-south-1` (Mumbai) | **Cluster:** `ecommerce-eks` | **Workstation:** `ubuntu-eks-devops-host` | **IAM Role:** `ubuntu-eks-devops-role`

## Overview

* Launch an Ubuntu Server 24.04 LTS EC2 instance (`ubuntu-eks-devops-host`) in **Asia Pacific (Mumbai) – `ap-south-1`** via the AWS Console.
* Attach the **`ubuntu-eks-devops-role`** IAM Instance Profile so all AWS CLI, Terraform, `eksctl`, and Secrets Manager commands authenticate securely without storing static AWS access keys on disk.
* Use this instance as your dedicated DevOps workstation to run Terraform, Docker, Java/Maven, `kubectl`, Helm, `eksctl`, and Git across Modules 1–12.

> **Cost & Security Note:** Choosing a smaller EC2 instance type (`t3.small`) helps keep workstation costs low for lab/learning setups, while restricting SSH/EC2 Instance Connect access, using an IAM Instance Profile instead of static keys, and keeping `.pem` keys secure protects your host.

## 1. Create the IAM Role & Policy (`ubuntu-eks-devops-role`)

Create an IAM Role for EC2 so Terraform, AWS CLI, `eksctl`, Helm, and Docker can provision and manage resources across Modules 1–12 (including VPC, EKS, IRSA/OIDC, ECR, ALB, S3 remote state, AWS Secrets Manager, and CloudWatch).

### 1.1 Create Customer-Managed Policy (`ubuntu-eks-devops-policy`)

* Navigate to **AWS Console → IAM → Policies → Create policy → JSON**.
* Paste the following policy JSON:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "ComputeNetworkingAndLoadBalancing",
      "Effect": "Allow",
      "Action": [
        "ec2:*",
        "elasticloadbalancing:*",
        "autoscaling:*"
      ],
      "Resource": "*"
    },
    {
      "Sid": "EKSClusterAndAddons",
      "Effect": "Allow",
      "Action": [
        "eks:*"
      ],
      "Resource": "*"
    },
    {
      "Sid": "IAMAndIRSAProvisioning",
      "Effect": "Allow",
      "Action": [
        "iam:CreateRole",
        "iam:DeleteRole",
        "iam:GetRole",
        "iam:PassRole",
        "iam:UpdateRole",
        "iam:TagRole",
        "iam:UntagRole",
        "iam:ListRolePolicies",
        "iam:ListAttachedRolePolicies",
        "iam:AttachRolePolicy",
        "iam:DetachRolePolicy",
        "iam:PutRolePolicy",
        "iam:DeleteRolePolicy",
        "iam:GetRolePolicy",
        "iam:CreatePolicy",
        "iam:DeletePolicy",
        "iam:GetPolicy",
        "iam:GetPolicyVersion",
        "iam:ListPolicyVersions",
        "iam:CreateOpenIDConnectProvider",
        "iam:DeleteOpenIDConnectProvider",
        "iam:GetOpenIDConnectProvider",
        "iam:TagOpenIDConnectProvider",
        "iam:ListOpenIDConnectProviders",
        "iam:CreateServiceLinkedRole"
      ],
      "Resource": "*"
    },
    {
      "Sid": "EksctlCloudFormationStacks",
      "Effect": "Allow",
      "Action": [
        "cloudformation:CreateStack",
        "cloudformation:UpdateStack",
        "cloudformation:DeleteStack",
        "cloudformation:DescribeStacks",
        "cloudformation:DescribeStackEvents",
        "cloudformation:DescribeStackResources",
        "cloudformation:ListStacks"
      ],
      "Resource": "arn:aws:cloudformation:ap-south-1:*:stack/eksctl-*"
    },
    {
      "Sid": "ECRContainerRegistry",
      "Effect": "Allow",
      "Action": [
        "ecr:*"
      ],
      "Resource": "*"
    },
    {
      "Sid": "TerraformStateS3Bucket",
      "Effect": "Allow",
      "Action": [
        "s3:CreateBucket",
        "s3:DeleteBucket",
        "s3:ListBucket",
        "s3:ListAllMyBuckets",
        "s3:GetBucketLocation",
        "s3:GetBucketVersioning",
        "s3:PutBucketVersioning",
        "s3:PutBucketPublicAccessBlock",
        "s3:PutEncryptionConfiguration",
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject",
        "s3:ListBucketVersions",
        "s3:DeleteObjectVersion"
      ],
      "Resource": [
        "arn:aws:s3:::eks-terraform-state-*",
        "arn:aws:s3:::eks-terraform-state-*/*"
      ]
    },
    {
      "Sid": "SecretsManagerProductionSecrets",
      "Effect": "Allow",
      "Action": [
        "secretsmanager:CreateSecret",
        "secretsmanager:DescribeSecret",
        "secretsmanager:GetSecretValue",
        "secretsmanager:PutSecretValue",
        "secretsmanager:UpdateSecret",
        "secretsmanager:DeleteSecret",
        "secretsmanager:TagResource",
        "secretsmanager:ListSecrets"
      ],
      "Resource": "*"
    },
    {
      "Sid": "CloudWatchObservabilityAndLogs",
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogGroup",
        "logs:DeleteLogGroup",
        "logs:DescribeLogGroups",
        "logs:PutRetentionPolicy",
        "logs:TagResource",
        "cloudwatch:PutMetricData",
        "cloudwatch:GetMetricData",
        "cloudwatch:ListMetrics"
      ],
      "Resource": "*"
    }
  ]
}
```

* Click **Next**, name the policy `ubuntu-eks-devops-policy`, and click **Create policy**.

### 1.2 Create the EC2 IAM Role (`ubuntu-eks-devops-role`)

* Navigate to **AWS Console → IAM → Roles → Create role**.
* Select **Trusted entity type:** `AWS service`, and **Use case:** `EC2` (this automatically sets `ec2.amazonaws.com` in the Trust Policy).
* Click **Next**, search for and select `ubuntu-eks-devops-policy` *(optional: also attach `AmazonSSMManagedInstanceCore` if using SSM Session Manager)*.
* Click **Next**, set **Role name** to `ubuntu-eks-devops-role`, and click **Create role**.
* **Verification:** `ubuntu-eks-devops-role` appears in **IAM → Roles** with `ubuntu-eks-devops-policy` attached.

## 2. Launch Ubuntu EC2 Instance in AWS Console

* Open the **AWS Console**, navigate to **EC2**, and select **Asia Pacific (Mumbai) – `ap-south-1`** in the top-right region selector.
* Click **Launch instance**.
* Set **Name** to `ubuntu-eks-devops-host`.
* Under **Application and OS Images (Amazon Machine Image)**, choose **Ubuntu** → **Ubuntu Server 24.04 LTS**.
* Under **Instance type**, select `t3.small`.
* Under **Key pair (login)**, click **Create new key pair**:
  * **Key pair name:** `ubuntu-eks-devops-host`
  * **Key pair type:** `RSA`
  * **Private key file format:** `.pem`
  * Click **Create key pair** and store `ubuntu-eks-devops-host.pem` securely.
* Under **Network settings**, configure your Security Group inbound rule for SSH (`TCP`, port `22`):
  * Choose **My IP** for local SSH access, **or**
  * Select the **`com.amazonaws.ap-south-1.ec2-instance-connect`** managed prefix list from the **Source** dropdown for browser-based EC2 Instance Connect.
* Under **Configure storage**, set the root volume to **30 GB** (`gp3`).
* Expand **Advanced details**, set **IAM instance profile** to `ubuntu-eks-devops-role`, and click **Launch instance**.
* **Verification:** Go to **EC2 → Instances** in `ap-south-1` and verify that `ubuntu-eks-devops-host` shows **Instance state: Running** with `ubuntu-eks-devops-role` attached under the **Security** tab.

## 3. Connect to EC2 Using EC2 Instance Connect (Web Browser)

* Navigate to **EC2 → Instances**.
* Select `ubuntu-eks-devops-host`.
* Click **Connect**.
* Select the **EC2 Instance Connect** tab.
* Enter username: `ubuntu`.
* Click **Connect**.

### Security Group Configuration for EC2 Instance Connect

For browser-based EC2 Instance Connect, configure the inbound SSH rule using the regional EC2 Instance Connect managed prefix list:

| Setting | Value | 
| ----- | ----- | 
| **Type** | SSH | 
| **Protocol** | TCP | 
| **Port** | 22 | 
| **Source** | `com.amazonaws.ap-south-1.ec2-instance-connect` | 

> **Important:**
>
> * Select the managed prefix list from the Security Group **Source** dropdown—do not enter it as a custom IP address.
> * Replace `ap-south-1` with your instance's actual AWS Region if using another Region.
> * The prefix list allows the EC2 Instance Connect service to reach your instance; it does not replace the IAM permissions required by the user initiating the connection.

* **Verification:** A browser terminal opens connected to `ubuntu@<private-or-public-ip>`.

## 4. Alternative: Connect Using AWS Systems Manager (SSM) Session Manager

If you prefer connecting without SSH or opening port 22, use **SSM Session Manager**:

* Attach the AWS managed policy `AmazonSSMManagedInstanceCore` to `ubuntu-eks-devops-role`.
* Ensure SSM Agent is installed and running.
* Allow outbound HTTPS traffic on port `443` to the required SSM endpoints.
* Ensure the instance has internet access or appropriate VPC endpoints.

> **Important:** `AmazonSSMManagedInstanceCore` is mandatory for the standard EC2 instance-based SSM setup. Port 22 is not required for Session Manager.

* **Verification:** Under **EC2 → Instances → Connect → Session Manager**, **Connect** is available and opens a shell as `ubuntu` or `ssm-user`.

## 5. Connect Using SSH Client

You can also connect to Ubuntu EC2 from your local machine using an SSH client and your downloaded private key:

* Open your SSH client (Terminal, PowerShell, or Git Bash).
* Locate `ubuntu-eks-devops-host.pem`.
* Restrict permissions on the private key file so it is not publicly viewable.

### Linux / macOS / Git Bash

```bash
chmod 400 "ubuntu-eks-devops-host.pem"
ssh -i "ubuntu-eks-devops-host.pem" ubuntu@<EC2-Public-DNS>
```

Example:

```bash
ssh -i "ubuntu-eks-devops-host.pem" ubuntu@ec2-XX-XX-XX-XX.ap-south-1.compute.amazonaws.com
```

*(Replace the example Public DNS with your actual EC2 Public DNS.)*

### Windows PowerShell

```powershell
ssh -i "C:\path\to\ubuntu-eks-devops-host.pem" ubuntu@<EC2-Public-DNS>
```

> **Note:** Ensure the Security Group allows inbound SSH (`TCP` port `22`) from your current public IP address.

* **Verification:** Your local terminal connects to `ubuntu@ip-...` without permission or timeout errors.

## 6. Important Notes

* Use the default Ubuntu username: `ubuntu`.
* Keep your `.pem` private key secure and never commit it to Git.
* Always attach `ubuntu-eks-devops-role` (with `ubuntu-eks-devops-policy`) to your EC2 workstation before running Terraform, `eksctl`, or AWS Secrets Manager commands in Modules 1–12.
* Ensure the EC2 instance has sufficient CPU, memory, and storage (`30 GB` `gp3`) for Docker builds, Maven builds, and Terraform providers.
* All modules and subsequent commands in this DevOps project are executed inside this Ubuntu EC2 instance.
