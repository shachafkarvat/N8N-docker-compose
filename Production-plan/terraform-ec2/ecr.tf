# ECR repository for the custom n8n image (base + cheerio).
# Image must be built and pushed BEFORE first terraform apply.
# The EC2 userdata pulls from this repo at boot.

resource "aws_ecr_repository" "n8n" {
  name                 = var.n8n_ecr_repo_name
  image_tag_mutability = "MUTABLE" # Allow :stable tag to be overwritten on updates
  force_delete         = false

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = local.tags
}

# Lifecycle policy: keep only the 5 most recent images to save storage costs
resource "aws_ecr_lifecycle_policy" "n8n" {
  repository = aws_ecr_repository.n8n.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep only 5 most recent images"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = 5
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}
