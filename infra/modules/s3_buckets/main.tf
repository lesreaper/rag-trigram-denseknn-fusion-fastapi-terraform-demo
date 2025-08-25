variable "project" {}
variable "raw_bucket_suffix" {}
variable "clean_bucket_suffix" {}
variable "common_tags" { type = map(string) }

resource "aws_s3_bucket" "raw" {
  bucket = "${var.project}-${var.raw_bucket_suffix}"
  force_destroy = true
  tags = var.common_tags
}

resource "aws_s3_bucket" "clean" {
  bucket = "${var.project}-${var.clean_bucket_suffix}"
  force_destroy = true
  tags = var.common_tags
}

output "raw_bucket" {
  value = aws_s3_bucket.raw.bucket
}

output "clean_bucket" {
  value = aws_s3_bucket.clean.bucket
}

# Allow browser preflight + PUT/GET/HEAD from your UI origins
resource "aws_s3_bucket_cors_configuration" "raw" {
  bucket = aws_s3_bucket.raw.id
  cors_rule {
    allowed_methods = ["PUT", "GET", "HEAD"]
    allowed_origins = [
      "elb url",
      "http://localhost:3000"
    ]
    allowed_headers = ["*"]
    expose_headers  = ["ETag", "x-amz-request-id", "x-amz-id-2"]
    max_age_seconds = 3600
  }
}

resource "aws_s3_bucket_cors_configuration" "clean" {
  bucket = aws_s3_bucket.clean.id
  cors_rule {
    allowed_methods = ["PUT", "GET", "HEAD"]
    allowed_origins = [
      "elb url",
      "http://localhost:3000"
    ]
    allowed_headers = ["*"]
    expose_headers  = ["ETag", "x-amz-request-id", "x-amz-id-2"]
    max_age_seconds = 3600
  }
}

