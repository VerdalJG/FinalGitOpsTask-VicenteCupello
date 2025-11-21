# High-Availability AWS Infrastructure (GitOps Pipeline)

This project uses **GitHub Actions**, **Terraform**, and **Ansible** to deploy a complete high-availability AWS architecture.  
The entire deployment is automated end-to-end following a GitOps workflow.

---

# Architecture Overview

## Components Created by Terraform

### **VPC**
- A dedicated Virtual Private Cloud (`10.0.0.0/16`)
- Acts as the container for all networking resources

### **Subnets**
- **2 Public Subnets** (in different AZs)
- **2 Private Subnets** (in different AZs)
- Public subnets have direct internet access through the Internet Gateway  
- Private subnets access the internet via a NAT Gateway (outbound only)

### **Routing**
- Public route table → routes `0.0.0.0/0` → Internet Gateway  
- Private route table → routes `0.0.0.0/0` → NAT Gateway  

### **Security Groups**
- **ALB SG**: allows HTTP/HTTPS from the internet  
- **EC2 SG**: allows HTTP/HTTPS **only from the ALB**, plus SSH from anywhere for Ansible  
- **RDS SG**: allows PostgreSQL only from EC2 instances  

### **Compute (EC2)**
- Launch Template defines AMI, instance type, security groups  
- Auto Scaling Group deploys **2–4 EC2 instances** across AZs  
- EC2s live in public subnets and register with an ALB target group

### **Load Balancing**
- Application Load Balancer in public subnets  
- Public entry point of the entire infrastructure  
- Distributes traffic across EC2 instances  

### **Database**
- RDS PostgreSQL in private subnets  
- No public exposure  
- Accessible only from EC2 instances (via SG rules)

---

# Network Diagram (ASCII)

```
                       ┌──────────────────────────────────────────┐
                       │               AWS VPC                    │
                       │             (10.0.0.0/16)                │
                       └──────────────────────────────────────────┘
                                      /                \
                                     /                  \
                         Public Subnets             Private Subnets
                     ┌─────────────────┐         ┌──────────────────┐
          AZ a ----> │  10.0.1.0/24    │         │10.0.11.0/24      │
                     │public_subnet_1  │         │private_subnet_1  │
                     └───────┬─────────┘         └─────────┬────────┘
                             │                             │
                             │                             │ 
                     ┌───────▼────────┐          ┌─────────▼──────────┐
          AZ c ----> │  10.0.2.0/24   │          │   10.0.12.0/24     │
                     │public_subnet_2 │          │  private_subnet_2  │
                     └───────┬────────┘          └─────────┬──────────┘
                             │                             │
                     ┌───────▼──────────┐        ┌─────────▼────────────┐
                     │ Internet Gateway │        │      NAT Gateway     │
                     └───────┬──────────┘        └─────────┬────────────┘
                             │                             │
                       Public internet           Outbound internet only
                             │                             │
                     ┌───────▼─────────────┐
                     │ Application LB      │
                     │ (Public entrypoint) │
                     └───────┬─────────────┘
                             │
                             ▼
                  ┌─────────────────────────┐
                  │  Auto Scaling Group     │
                  │  EC2 Web Instances      │
                  └───────────┬─────────────┘
                              │
                              ▼
                  ┌──────────────────────────┐
                  │ RDS PostgreSQL (Private) │
                  └──────────────────────────┘
```

---

# ⚙️ GitHub Actions Workflow

This workflow automatically:

1. Checks out repository
2. Configures AWS credentials
3. Runs Terraform:
   - `init`
   - `validate`
   - `plan`
   - `apply`
4. Extracts the ALB DNS name from Terraform outputs
5. Configures SSH key for Ansible
6. Installs Ansible + AWS SDK dependencies
7. Runs the Ansible playbook to configure EC2 instances

### Workflow File

````yaml
name: Deploy high availability AWS infrastructure

on:
  workflow_dispatch:

jobs:
  deploy:
    runs-on: ubuntu-latest

    steps:
      - name: Checkout
        uses: actions/checkout@v5.0.1

      - name: Set up AWS credentials
        run: |
          echo "AWS_ACCESS_KEY_ID=${{ secrets.AWS_ACCESS_KEY_ID }}" >> $GITHUB_ENV
          echo "AWS_SECRET_ACCESS_KEY=${{ secrets.AWS_SECRET_ACCESS_KEY }}" >> $GITHUB_ENV
          echo "AWS_REGION=${{ secrets.AWS_REGION }}" >> $GITHUB_ENV

      - name: Setup Terraform
        uses: hashicorp/setup-terraform@v3.1.2
        with:
          terraform_version: "1.13.4"

      - name: Terraform Init
        run: |
          cd Terraform
          terraform init

      - name: Terraform Plan
        run: |
          cd Terraform
          terraform validate
          terraform plan -var="aws_region=${{ secrets.AWS_REGION }}" -out=tfplan

      - name: Terraform Apply
        run: |
          cd Terraform
          terraform apply -var="aws_region=${{ secrets.AWS_REGION }}" -auto-approve tfplan

      - name: Capture ALB DNS
        run: |
          cd Terraform
          alb_dns=$(terraform output -raw alb_dns_name)
          echo "ALB_DNS=$alb_dns" >> $GITHUB_ENV

      - name: Setup SSH key for Ansible
        run: |
          mkdir -p ~/.ssh
          echo "${{ secrets.EC2_SSH_PRIVATE_KEY }}" > ~/.ssh/id_rsa
          chmod 600 ~/.ssh/id_rsa

      - name: Install Ansible AWS dependencies
        run: |
          python3 -m pip install --upgrade pip
          pip install ansible boto3 botocore jq

      - name: Run Ansible Playbook
        run: |
          cd Ansible
          ansible-playbook playbook.yml --user ubuntu -e "alb_dns=$ALB_DNS"
        env:
          AWS_DEFAULT_REGION: ${{ secrets.AWS_REGION }}
          ALB_DNS: ${{ env.ALB_DNS }}
