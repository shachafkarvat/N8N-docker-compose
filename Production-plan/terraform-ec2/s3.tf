resource "aws_s3_bucket" "backups" {
  bucket = var.backup_bucket_name
  tags   = local.tags
}

resource "aws_s3_bucket_versioning" "backups" {
  bucket = aws_s3_bucket.backups.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_public_access_block" "backups" {
  bucket = aws_s3_bucket.backups.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "backups" {
  bucket = aws_s3_bucket.backups.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "backups" {
  bucket = aws_s3_bucket.backups.id

  rule {
    id     = "daily-retention"
    status = "Enabled"
    filter { prefix = "daily/" }
    expiration { days = 7 }
  }

  rule {
    id     = "weekly-retention"
    status = "Enabled"
    filter { prefix = "weekly/" }
    expiration { days = 28 }
  }

  rule {
    id     = "monthly-retention"
    status = "Enabled"
    filter { prefix = "monthly/" }
    expiration { days = 365 }
  }
}

resource "aws_s3_bucket" "config" {
  bucket = var.config_bucket_name
  tags   = local.tags
}

resource "aws_s3_bucket_versioning" "config" {
  bucket = aws_s3_bucket.config.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_public_access_block" "config" {
  bucket = aws_s3_bucket.config.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "config" {
  bucket = aws_s3_bucket.config.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_object" "docker_compose" {
  bucket = aws_s3_bucket.config.id
  key    = var.config_compose_key
  content = templatefile("${path.module}/templates/docker-compose.yml.tpl", {
    fqdn           = local.fqdn
    timezone       = var.timezone
    ecr_repo_url   = aws_ecr_repository.n8n.repository_url
    ecr_image_tag  = var.n8n_image_tag
    use_alb        = var.enable_alb
    n8n_proxy_hops = local.n8n_proxy_hops
  })
  content_type = "text/yaml"
  etag = md5(templatefile("${path.module}/templates/docker-compose.yml.tpl", {
    fqdn           = local.fqdn
    timezone       = var.timezone
    ecr_repo_url   = aws_ecr_repository.n8n.repository_url
    ecr_image_tag  = var.n8n_image_tag
    use_alb        = var.enable_alb
    n8n_proxy_hops = local.n8n_proxy_hops
  }))

  depends_on = [aws_s3_bucket_versioning.config]
}
