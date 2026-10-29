###############################################################################
# environments/prod/main.tf
#
# Root module for the production environment.
# Wires together: VPC → Security Groups → IAM → ECR → k3s Cluster
#
# Prerequisites
# -------------
#   1. Run `cd terraform/bootstrap && terraform apply` first to create the
#      S3 bucket and DynamoDB table, then update backend.tf below.
#   2. Copy terraform.tfvars.example → terraform.tfvars and fill in values.
###############################################################################

###############################################################################
# VPC
###############################################################################

module "vpc" {
  source = "../../modules/vpc"

  project     = var.project
  environment = var.environment

  vpc_cidr        = var.vpc_cidr
  public_subnets  = var.public_subnets
  private_subnets = var.private_subnets
  azs             = var.azs

  tags = local.common_tags
}

###############################################################################
# Security Groups
###############################################################################

module "security_groups" {
  source = "../../modules/security-groups"

  project     = var.project
  environment = var.environment

  vpc_id            = module.vpc.vpc_id
  vpc_cidr          = module.vpc.vpc_cidr_block
  ssh_allowed_cidrs = var.ssh_allowed_cidrs

  tags = local.common_tags
}

###############################################################################
# IAM
###############################################################################

module "iam" {
  source = "../../modules/iam"

  project     = var.project
  environment = var.environment
  aws_region  = var.aws_region

  ses_sender_email            = var.ses_sender_email
  create_github_oidc_role     = var.create_github_oidc_role
  create_github_oidc_provider = var.create_github_oidc_provider
  github_repo                 = var.github_repo
  tfstate_bucket          = var.tfstate_bucket
  tflock_table            = var.tflock_table

  tags = local.common_tags
}

###############################################################################
# ECR
###############################################################################

module "ecr" {
  source = "../../modules/ecr"

  project     = var.project
  environment = var.environment

  repositories            = var.ecr_repositories
  k3s_node_role_arn       = module.iam.k3s_node_role_arn
  github_actions_role_arn = module.iam.github_actions_role_arn

  tags = local.common_tags

  depends_on = [module.iam]
}

###############################################################################
# k3s Cluster
###############################################################################

module "k3s" {
  source = "../../modules/k3s-cluster"

  project     = var.project
  environment = var.environment
  aws_region  = var.aws_region

  public_subnet_id      = module.vpc.public_subnet_ids[0]
  security_group_id     = module.security_groups.k3s_server_sg_id
  instance_profile_name = module.iam.k3s_instance_profile_name

  instance_type       = var.k3s_instance_type
  root_volume_size_gb = var.root_volume_size_gb
  k3s_version         = var.k3s_version
  public_key_material = var.ssh_public_key

  tags = local.common_tags

  depends_on = [module.vpc, module.security_groups, module.iam]
}
