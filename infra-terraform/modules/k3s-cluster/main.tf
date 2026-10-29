###############################################################################
# k3s Cluster Module
#
# Provisions a single-node k3s cluster on EC2 with:
#   • Latest Amazon Linux 2023 AMI (auto-resolved via SSM)
#   • EBS root volume with encryption
#   • user-data script that installs k3s, waits for the API, and
#     writes the kubeconfig to SSM Parameter Store
#   • Elastic IP for stable DNS / kubeconfig endpoint
#   • SSM Parameter Store entry holding the kubeconfig
###############################################################################

###############################################################################
# Data sources
###############################################################################

data "aws_ssm_parameter" "al2023_ami" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

###############################################################################
# Key Pair (optional – provide your public key)
###############################################################################

resource "aws_key_pair" "k3s" {
  count      = var.public_key_material != "" ? 1 : 0
  key_name   = "${var.project}-${var.environment}-k3s"
  public_key = var.public_key_material

  tags = var.tags
}

###############################################################################
# EIP – stable public IP for kubeconfig / API access
###############################################################################

resource "aws_eip" "k3s" {
  domain = "vpc"

  tags = merge(var.tags, {
    Name = "${var.project}-${var.environment}-k3s-eip"
  })
}

resource "aws_eip_association" "k3s" {
  instance_id   = aws_instance.k3s.id
  allocation_id = aws_eip.k3s.id
}

###############################################################################
# User-Data script
# Runs on first boot:
#   1. Update packages & install awscli, jq
#   2. Install k3s (latest stable)
#   3. Wait for the API server to become healthy
#   4. Patch the kubeconfig to use the EIP
#   5. Upload kubeconfig → SSM Parameter Store (SecureString)
###############################################################################

locals {
  user_data = <<-USERDATA
    #!/bin/bash
    set -euxo pipefail
    exec > >(tee /var/log/user-data.log | logger -t user-data -s 2>/dev/console) 2>&1

    #---------------------------------------------------------------------------
    # 1. System updates
    #---------------------------------------------------------------------------
    dnf update -y
    dnf install -y --allowerasing awscli jq git

    #---------------------------------------------------------------------------
    # 2. Install k3s
    #    INSTALL_K3S_EXEC flags:
    #      --write-kubeconfig-mode 644  → readable by ec2-user for debugging
    #      --tls-san <EIP>        → kubeconfig SAN includes the public IP
    #---------------------------------------------------------------------------
    INSTALL_K3S_VERSION="${var.k3s_version}"
    EIP="${aws_eip.k3s.public_ip}"

    curl -sfL https://get.k3s.io | \
      INSTALL_K3S_VERSION="$INSTALL_K3S_VERSION" \
      sh -s - server \
        --write-kubeconfig-mode 644 \
        --tls-san "$EIP"

    #---------------------------------------------------------------------------
    # 3. Wait for the API server
    #---------------------------------------------------------------------------
    echo "Waiting for k3s API..."
    until kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml get nodes 2>/dev/null; do
      sleep 5
    done
    echo "k3s API is ready."

    #---------------------------------------------------------------------------
    # 4. Patch kubeconfig – replace 127.0.0.1 with the EIP so it works remotely
    #---------------------------------------------------------------------------
    KUBECONFIG_RAW=$(cat /etc/rancher/k3s/k3s.yaml)
    KUBECONFIG_PATCHED=$(echo "$KUBECONFIG_RAW" | sed "s|127.0.0.1|$EIP|g")

    #---------------------------------------------------------------------------
    # 5. Upload kubeconfig to SSM Parameter Store
    #---------------------------------------------------------------------------
    REGION="${var.aws_region}"
    aws ssm put-parameter \
      --region "$REGION" \
      --name "/${var.project}/${var.environment}/k3s/kubeconfig" \
      --value "$KUBECONFIG_PATCHED" \
      --type SecureString \
      --overwrite

    echo "kubeconfig uploaded to SSM."

    #---------------------------------------------------------------------------
    # 6. Install Metrics Server (required for kubectl top and HPA)
    #---------------------------------------------------------------------------
    kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml apply -f \
      https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

    #---------------------------------------------------------------------------
    # 7. Tag the root EBS volume
    #---------------------------------------------------------------------------
    IMDS_TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
    INSTANCE_ID=$(curl -s -H "X-aws-ec2-metadata-token: $IMDS_TOKEN" http://169.254.169.254/latest/meta-data/instance-id)
    VOL_ID=$(aws ec2 describe-instances --region "$REGION" \
      --instance-ids "$INSTANCE_ID" \
      --query 'Reservations[0].Instances[0].BlockDeviceMappings[0].Ebs.VolumeId' \
      --output text)
    aws ec2 create-tags --region "$REGION" --resources "$VOL_ID" \
      --tags Key=Name,Value="${var.project}-${var.environment}-k3s-root"

    echo "Bootstrap complete."
  USERDATA
}

###############################################################################
# EC2 Instance
###############################################################################

resource "aws_instance" "k3s" {
  ami                    = data.aws_ssm_parameter.al2023_ami.value
  instance_type          = var.instance_type
  subnet_id              = var.public_subnet_id
  vpc_security_group_ids = [var.security_group_id]
  iam_instance_profile   = var.instance_profile_name
  key_name               = var.public_key_material != "" ? aws_key_pair.k3s[0].key_name : null

  # IMDS v2 enforced (security best practice)
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required" # IMDSv2
    http_put_response_hop_limit = 2          # allows containers to reach IMDS
  }

  root_block_device {
    volume_type           = "gp3"
    volume_size           = var.root_volume_size_gb
    encrypted             = true
    delete_on_termination = true
  }

  user_data                   = local.user_data
  user_data_replace_on_change = false # don't recreate on minor user-data tweaks

  tags = merge(var.tags, {
    Name = "${var.project}-${var.environment}-k3s-server"
    Role = "k3s-server"
  })

  lifecycle {
    ignore_changes = [ami] # don't replace on AMI updates; use a replacement flow
  }
}

###############################################################################
# SSM Parameter – kubeconfig path (value written by user-data above)
###############################################################################

resource "aws_ssm_parameter" "kubeconfig_path" {
  name  = "/${var.project}/${var.environment}/k3s/kubeconfig-param-name"
  type  = "String"
  value = "/${var.project}/${var.environment}/k3s/kubeconfig"

  tags = var.tags
}

###############################################################################
# CloudWatch Log Group – k3s / container logs
###############################################################################

resource "aws_cloudwatch_log_group" "k3s" {
  name              = "/aws/ec2/${var.project}-${var.environment}/k3s"
  retention_in_days = 30

  tags = var.tags
}
