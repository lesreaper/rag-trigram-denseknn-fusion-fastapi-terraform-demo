# iam.tf
resource "aws_iam_role" "task" {
  name = "${var.project}-task-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect    = "Allow",
      Principal = { Service = "ecs-tasks.amazonaws.com" },
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "task_s3" {
  name = "${var.project}-task-s3"
  role = aws_iam_role.task.id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      # objects in the buckets
      {
        Effect = "Allow",
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:AbortMultipartUpload",
          "s3:ListBucketMultipartUploads"
        ],
        Resource = [
          "arn:aws:s3:::${var.raw_bucket}/*",
          "arn:aws:s3:::${var.clean_bucket}/*"
        ]
      },
      # (optional) list bucket to check existence
      {
        Effect = "Allow",
        Action = ["s3:ListBucket"],
        Resource = [
          "arn:aws:s3:::${var.raw_bucket}",
          "arn:aws:s3:::${var.clean_bucket}"
        ]
      }
    ]
  })
}

resource "aws_iam_role" "exec" {
  name = "${var.project}-exec-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect    = "Allow",
      Principal = { Service = "ecs-tasks.amazonaws.com" },
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "exec_ecs_managed" {
  role       = aws_iam_role.exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# (optional) logs helper
resource "aws_iam_role_policy_attachment" "exec_logs" {
  role       = aws_iam_role.exec.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchLogsFullAccess"
}
