# awsecsmongodb
Example code for blog post [Streamlining MongoDB Deployment on AWS ECS with Terraform](https://gooogle.com).

## Setup

```bash
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars - restrict ssh_allowed_cidrs and mongodb_allowed_cidrs for production
terraform init
terraform apply
```

## Redeploy

**Refresh credentials first** (if using SSO or temporary tokens):
```bash
aws sso login
```

**Replace EC2 instance** (keeps Elastic IP, picks up AMI/user-data/config changes):
```bash
terraform taint aws_instance.mongolab_ec2_instance
terraform apply
```

**Full teardown and recreate:**
```bash
terraform destroy
terraform apply
```

## MongoDB (EC2)

- **Persistence:** Data is stored on an EBS volume at `/var/lib/mongo` and survives instance replacement.
- **Auth:** Uses credentials from SSM (mongodb_root_username, mongodb_root_password in tfvars).
- **Connect:** `mongosh "mongodb://USERNAME:PASSWORD@EC2_IP:27017"`
- **Restrict access:** Set `mongodb_allowed_cidrs = ["YOUR_IP/32"]` in terraform.tfvars.

## AWS architecture diagram
![AWS Architecture Diagram](.diagram/awsecsmongo.png)

## License
This code is licensed under the MIT License.