###############################################################################
# Makefile – AI SRE Agent Infrastructure Operations
#
# Usage:
#   make bootstrap          – Create S3 state bucket + DynamoDB lock table
#   make init               – Initialise prod Terraform
#   make plan               – Plan prod changes
#   make apply              – Apply prod changes
#   make kubeconfig         – Fetch kubeconfig from SSM to ~/.kube/
#   make destroy            – Destroy prod infrastructure (DANGEROUS)
###############################################################################

SHELL := /bin/bash
PROD_DIR := environments/prod
BOOTSTRAP_DIR := bootstrap
REGION := ap-south-1
PROJECT := ai-sre-agent
ENV := prod

.PHONY: bootstrap bootstrap-init bootstrap-apply \
        init plan apply destroy \
        kubeconfig output validate fmt \
        help

# ─── Bootstrap ──────────────────────────────────────────────────────────────

bootstrap: bootstrap-init bootstrap-apply

bootstrap-init:
	@echo "==> Initialising bootstrap..."
	cd $(BOOTSTRAP_DIR) && terraform init

bootstrap-apply:
	@echo "==> Applying bootstrap (S3 + DynamoDB)..."
	cd $(BOOTSTRAP_DIR) && terraform apply -auto-approve
	@echo ""
	@echo "==> Bootstrap outputs:"
	cd $(BOOTSTRAP_DIR) && terraform output
	@echo ""
	@echo "IMPORTANT: Copy the bucket name and table name into:"
	@echo "  $(PROD_DIR)/backend.tf"
	@echo "  $(PROD_DIR)/terraform.tfvars"

# ─── Production Environment ──────────────────────────────────────────────────

init:
	@echo "==> Initialising prod environment..."
	cd $(PROD_DIR) && terraform init -upgrade

validate:
	cd $(PROD_DIR) && terraform validate

fmt:
	terraform fmt -recursive .

plan:
	@echo "==> Planning prod changes..."
	cd $(PROD_DIR) && terraform plan -out=tfplan

apply:
	@echo "==> Applying prod changes..."
	cd $(PROD_DIR) && terraform apply tfplan

apply-auto:
	@echo "==> Applying prod changes (auto-approve)..."
	cd $(PROD_DIR) && terraform apply -auto-approve

output:
	cd $(PROD_DIR) && terraform output

destroy:
	@echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
	@echo "WARNING: This will DESTROY all infrastructure!"
	@echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
	@read -p "Type 'yes' to confirm: " confirm && [ "$$confirm" = "yes" ] || exit 1
	cd $(PROD_DIR) && terraform destroy

# ─── kubeconfig ──────────────────────────────────────────────────────────────

kubeconfig:
	@echo "==> Fetching kubeconfig from SSM..."
	@mkdir -p ~/.kube
	aws ssm get-parameter \
	  --region $(REGION) \
	  --name "/$(PROJECT)/$(ENV)/k3s/kubeconfig" \
	  --with-decryption \
	  --query "Parameter.Value" \
	  --output text > ~/.kube/$(PROJECT)-$(ENV).yaml
	@chmod 600 ~/.kube/$(PROJECT)-$(ENV).yaml
	@echo "==> Kubeconfig written to ~/.kube/$(PROJECT)-$(ENV).yaml"
	@echo "==> Run: export KUBECONFIG=~/.kube/$(PROJECT)-$(ENV).yaml"
	@kubectl --kubeconfig ~/.kube/$(PROJECT)-$(ENV).yaml get nodes

# ─── Help ────────────────────────────────────────────────────────────────────

help:
	@echo ""
	@echo "AI SRE Agent – Terraform Operations"
	@echo "===================================="
	@echo ""
	@echo "  make bootstrap      Create S3 state bucket + DynamoDB lock table"
	@echo "  make init           Initialise Terraform in environments/prod"
	@echo "  make validate       Validate Terraform configuration"
	@echo "  make fmt            Format all .tf files"
	@echo "  make plan           Generate and save a plan"
	@echo "  make apply          Apply the saved plan"
	@echo "  make apply-auto     Apply with -auto-approve (CI/CD)"
	@echo "  make output         Show Terraform outputs"
	@echo "  make kubeconfig     Fetch kubeconfig from SSM Parameter Store"
	@echo "  make destroy        Destroy all infrastructure (DANGEROUS)"
	@echo ""
