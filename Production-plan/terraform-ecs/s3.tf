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
