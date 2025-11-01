terraform {
  backend "s3" {
  }
}

// S3 bucket
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
      days          = 2
      storage_class = "DEEP_ARCHIVE"
    }

    expiration {
      days = 180
    }
  }
}


// SNS
resource "aws_sns_topic" "email_notifications" {
  name = "noti-on-backup-failure-topic"
}

resource "aws_sns_topic_subscription" "admin_email_subscription" {
  topic_arn = aws_sns_topic.email_notifications.arn
  protocol  = "email"
  endpoint  = var.notification_email
}

// IAM user to backup
resource "aws_iam_user" "vw_backup_usr" {
  name = "vaultwarden-backup-usr"
  path = "/"

  tags = {
    Purpose   = "backup"
    Service   = "vaultwarden"
    ManagedBy = "terraform"
  }
}

data "aws_iam_policy_document" "vw_backup_min" {
  statement {
    sid       = "S3ListBucketForPrefix"
    actions   = ["s3:ListBucket", "s3:GetBucketLocation"]
    resources = [aws_s3_bucket.vaultwarden_backup.arn]

    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values   = ["*"]
    }
  }

  statement {
    sid       = "S3ListBucketMultipartUploads"
    actions   = ["s3:ListBucketMultipartUploads"]
    resources = [aws_s3_bucket.vaultwarden_backup.arn]
  }

  statement {
    sid = "S3ObjectCpOnly"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:AbortMultipartUpload",
      "s3:ListMultiPartUploadParts",
    ]
    resources = ["${aws_s3_bucket.vaultwarden_backup.arn}/*"]
  }

  statement {
    sid       = "SnsPublishOnly"
    actions   = ["sns:Publish"]
    resources = [aws_sns_topic.email_notifications.arn]
  }
}

resource "aws_iam_policy" "vw_backup_min" {
  name   = "vw-backup-minimal"
  policy = data.aws_iam_policy_document.vw_backup_min.json
}

resource "aws_iam_user_policy_attachment" "vw_backup_attach" {
  user       = aws_iam_user.vw_backup_usr.name
  policy_arn = aws_iam_policy.vw_backup_min.arn


}
