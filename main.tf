terraform {
  backend "s3" {
  }
}

resource "aws_s3_bucket" "vaultwarden_backup" {
  bucket = var.backup_bucket_name

  tags = {
    Name = "vaultwarden-backup-bucket"
  }

}

resource "aws_s3_bucket_server_side_encryption_configuration" "backup_sse" {
  bucket = aws_s3_bucket.vaultwarden_backup.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "vault_public_access" {
  bucket                  = aws_s3_bucket.vaultwarden_backup.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "backup_lifecycle" {
  bucket = aws_s3_bucket.vaultwarden_backup.id

  rule {
    id     = "move-to-glacier"
    status = "Enabled"

    filter {
      prefix = ""
    }

    transition {
      days          = 0
      storage_class = "GLACIER_IR"
    }

    expiration {
      days = 365
    }
  }
}

resource "aws_sns_topic" "email_notifications" {
  name = "noti-on-backup-failure-topic"
}

resource "aws_sns_topic_subscription" "admin_email_subscription" {
  topic_arn = aws_sns_topic.email_notifications.arn
  protocol  = "email"
  endpoint  = var.notification_email
}
