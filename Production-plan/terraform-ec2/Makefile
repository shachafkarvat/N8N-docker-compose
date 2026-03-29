# ── n8n Production – terraform-ec2 ────────────────────────────────────────
#
# Usage:
#   make init          Initialise Terraform (backend + providers)
#   make fmt           Format .tf files
#   make validate      Validate configuration
#   make plan          Preview changes
#   make apply         Apply changes (requires confirmation)
#   make destroy       Tear down all resources (requires confirmation)
#
#   make bootstrap     Create S3 state bucket + DynamoDB lock table
#   make ecr           Create the ECR repository via targeted apply
#   make docker-push   Build the custom n8n image and push to ECR
#
# Override defaults on the command line:
#   make docker-push IMAGE_TAG=v1.2.3
# ──────────────────────────────────────────────────────────────────────────

AWS_REGION   ?= eu-west-2
ECR_REPO     ?= taurak/n8n
IMAGE_TAG    ?= stable
DOCKERFILE   ?= ../../n8n.Dockerfile
DOCKER_CTX   ?= ../..

# Resolved at runtime
AWS_ACCOUNT  := $(shell aws sts get-caller-identity --query Account --output text)
ECR_REGISTRY := $(AWS_ACCOUNT).dkr.ecr.$(AWS_REGION).amazonaws.com
ECR_IMAGE    := $(ECR_REGISTRY)/$(ECR_REPO)

# ── Terraform ─────────────────────────────────────────────────────────────

.PHONY: init fmt validate plan apply destroy

init:
	terraform init

fmt:
	terraform fmt -recursive

validate: init
	terraform validate

plan: init
	terraform plan

apply: init
	terraform apply

destroy: init
	terraform destroy

# ── Bootstrap ─────────────────────────────────────────────────────────────

.PHONY: bootstrap

bootstrap:
	@echo "==> Creating S3 state bucket and DynamoDB lock table..."
	bash ../scripts/bootstrap-state.sh

# ── ECR ───────────────────────────────────────────────────────────────────

.PHONY: ecr

ecr: init
	@echo "==> Creating ECR repository (targeted apply)..."
	terraform apply -target=aws_ecr_repository.n8n -target=aws_ecr_lifecycle_policy.n8n

# ── Docker build & push ──────────────────────────────────────────────────

.PHONY: docker-login docker-build docker-push

docker-login:
	aws ecr get-login-password --region $(AWS_REGION) | \
		docker login --username AWS --password-stdin $(ECR_REGISTRY)

docker-build:
	docker build --platform linux/arm64 -f $(DOCKERFILE) -t $(ECR_IMAGE):$(IMAGE_TAG) $(DOCKER_CTX)

docker-push: docker-login docker-build
	docker push $(ECR_IMAGE):$(IMAGE_TAG)
	@echo "==> Pushed $(ECR_IMAGE):$(IMAGE_TAG)"
