resource "aws_s3_bucket" "backups" {
  bucket = var.backup_bucket_name
}

resource "aws_s3_bucket_versioning" "backups" {
  bucket = aws_s3_bucket.backups.id
  versioning_configuration {
    status = "Enabled"
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
