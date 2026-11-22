# Prerequisites – Create & Connect to Ubuntu EC2 Workstation

**Region:** `ap-south-1` (Mumbai) | **Cluster:** `ecommerce-eks` | **Workstation:** `ubuntu-eks-devops-host`

## Overview

Create an Ubuntu EC2 instance in **Asia Pacific (Mumbai) – `ap-south-1`** in the AWS Console. This instance acts as a dedicated Linux workstation to run Terraform, Docker, Java/Maven, `kubectl`, Helm, `eksctl`, and Git without cluttering your local machine.

> **Cost & Security Note:** Choosing a smaller EC2 instance type helps keep workstation costs low for lab/learning setups, while restricting SSH/EC2 Instance Connect access and keeping `.pem` keys secure protects your host.

---

## 1. Launch Ubuntu EC2 Instance in AWS Console

1. Navigate to **AWS Console → EC2 → Launch instance**.
2. Select Region: **Asia Pacific (Mumbai) – `ap-south-1`**.
3. Configure the instance details:

| Setting | Configuration |
| --- | --- |
| **Instance Name** | `ubuntu-eks-devops-host` |
| **AMI** | Ubuntu Server 24.04 LTS |
| **Instance Type** | `t3.small` |
| **Root Storage** | `30 GB` `gp3` |
| **Key Pair** | `ubuntu-eks-devops-host.pem` |
| **Security Group** | Allow SSH (`TCP 22`) from your IP |

### Configure Key Pair
1. Under **Key pair (login)**, click **Create new key pair**.
2. **Key pair name:** `ubuntu-eks-devops-host`
3. **Key pair type:** `RSA`
4. **Private key file format:** `.pem`
5. Click **Create key pair**, then download and securely store `ubuntu-eks-devops-host.pem`.

### Configure Security Group
Create or select a Security Group with the following inbound rule:

| Type | Protocol | Port | Source |
| --- | --- | --- | --- |
| SSH | TCP | 22 | My IP |

4. Click **Launch instance**.

* **Verification:** `ubuntu-eks-devops-host` appears under **EC2 → Instances** in `ap-south-1` with **Instance state** set to `Running`.

---

## 2. Connect to EC2 Using EC2 Instance Connect (Web Browser)

1. Navigate to **EC2 → Instances**.
2. Select `ubuntu-eks-devops-host`.
3. Click **Connect**.
4. Select the **EC2 Instance Connect** tab.
5. Enter username: `ubuntu`.
6. Click **Connect**.

### Security Group Configuration for EC2 Instance Connect
For browser-based EC2 Instance Connect, configure the inbound SSH rule using the regional EC2 Instance Connect managed prefix list:

| Setting | Value |
| --- | --- |
| **Type** | SSH |
| **Protocol** | TCP |
| **Port** | 22 |
| **Source** | `com.amazonaws.ap-south-1.ec2-instance-connect` |

> **Important:**
> * Select the managed prefix list from the Security Group **Source** dropdown—do not enter it as a custom IP address.
> * Replace `ap-south-1` with your instance's actual AWS Region if using another Region.
> * The prefix list allows the EC2 Instance Connect service to reach your instance; it does not replace the IAM permissions required by the user initiating the connection.

* **Verification:** A browser terminal opens connected to `ubuntu@<private-or-public-ip>`.

---

## 3. Alternative: Connect Using AWS Systems Manager (SSM) Session Manager

If you prefer connecting without SSH or opening port 22, use **SSM Session Manager**:

* Attach an IAM role to the EC2 instance.
* Attach the AWS managed policy `AmazonSSMManagedInstanceCore`.
* Ensure SSM Agent is installed and running.
* Allow outbound HTTPS traffic on port `443` to the required SSM endpoints.
* Ensure the instance has internet access or appropriate VPC endpoints.

> **Important:** An IAM role with `AmazonSSMManagedInstanceCore` is mandatory for the standard EC2 instance-based SSM setup. Port 22 is not required for Session Manager.

* **Verification:** Under **EC2 → Instances → Connect → Session Manager**, **Connect** is available and opens a shell as `ubuntu` or `ssm-user`.

---

## 4. Connect Using SSH Client

You can also connect to Ubuntu EC2 from your local machine using an SSH client and your downloaded private key:

1. Open your SSH client (Terminal, PowerShell, or Git Bash).
2. Locate `ubuntu-eks-devops-host.pem`.
3. Restrict permissions on the private key file so it is not publicly viewable.

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

---

## 5. Important Notes

* Use the default Ubuntu username: `ubuntu`.
* Keep your `.pem` private key secure and never commit it to Git.
* EC2 Instance Connect requires appropriate IAM permissions for the connecting user or role.
* An IAM role on the EC2 instance is not required for standard SSH or EC2 Instance Connect, though it is required for SSM Session Manager and later AWS CLI/Terraform operations.
* Ensure the EC2 instance has sufficient CPU, memory, and storage for your DevOps workloads.
* All modules and subsequent commands in this DevOps project are executed inside this Ubuntu EC2 instance.
