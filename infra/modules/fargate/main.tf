# =============================================================================
# 1. ECR repository -- stores the websocket-relay container image
# =============================================================================
resource "aws_ecr_repository" "websocket_relay" {
  name                 = "${var.project}-websocket-relay"
  image_tag_mutability = "MUTABLE" # dev; prod would be IMMUTABLE for supply-chain safety

  image_scanning_configuration {
    scan_on_push = true # free basic vuln scan on every push
  }

  encryption_configuration {
    encryption_type = "KMS"
    kms_key         = var.kms_key_arn
  }

  tags = { Module = "fargate" }
}

# Keep only the 5 most recent images to control storage cost.
resource "aws_ecr_lifecycle_policy" "keep_last_5" {
  repository = aws_ecr_repository.websocket_relay.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep last 5 images, delete older"
      selection = {
        tagStatus     = "any"
        countType     = "imageCountMoreThan"
        countNumber   = 5
      }
      action = { type = "expire" }
    }]
  })
}

# =============================================================================
# 2. IAM: two roles
#    - task execution role: used by Fargate runtime (ECR pull + logs + secrets)
#    - task role: used by app code (Kinesis PutRecord + read the secret)
# =============================================================================

# ---- Task execution role ----
data "aws_iam_policy_document" "task_exec_trust" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "task_exec" {
  name               = "${var.project}-fargate-exec-role"
  assume_role_policy = data.aws_iam_policy_document.task_exec_trust.json
  tags               = { Module = "fargate", Purpose = "task-execution" }
}

# AWS-managed policy covers ECR pull + CloudWatch logs write. Enough for standard use.
resource "aws_iam_role_policy_attachment" "task_exec_managed" {
  role       = aws_iam_role.task_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Extra: ECR encryption key + Secrets Manager decrypt (for SECRETS env var injection if ever used).
data "aws_iam_policy_document" "task_exec_extras" {
  statement {
    sid       = "DecryptViaEcrAndSm"
    actions   = ["kms:Decrypt"]
    resources = [var.kms_key_arn]
    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = [
        "ecr.${var.aws_region}.amazonaws.com",
        "secretsmanager.${var.aws_region}.amazonaws.com",
      ]
    }
  }
}

resource "aws_iam_role_policy" "task_exec_extras" {
  name   = "${var.project}-fargate-exec-extras"
  role   = aws_iam_role.task_exec.id
  policy = data.aws_iam_policy_document.task_exec_extras.json
}

# ---- Task role (application-code identity) ----
data "aws_iam_policy_document" "task_role_permissions" {
  statement {
    sid       = "ReadSecret"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [var.secret_arn]
  }

  statement {
    sid       = "DecryptSecret"
    actions   = ["kms:Decrypt"]
    resources = [var.kms_key_arn]
    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["secretsmanager.${var.aws_region}.amazonaws.com"]
    }
  }

  statement {
    sid       = "PublishToStream"
    actions   = ["kinesis:PutRecord", "kinesis:PutRecords", "kinesis:DescribeStream"]
    resources = [var.kinesis_stream_arn]
  }

  statement {
    sid       = "KinesisEncrypt"
    actions   = ["kms:GenerateDataKey", "kms:Decrypt"]
    resources = [var.kms_key_arn]
    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["kinesis.${var.aws_region}.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "task_role" {
  name               = "${var.project}-fargate-task-role"
  assume_role_policy = data.aws_iam_policy_document.task_exec_trust.json
  tags               = { Module = "fargate", Purpose = "app-runtime" }
}

resource "aws_iam_role_policy" "task_role" {
  name   = "${var.project}-fargate-task-policy"
  role   = aws_iam_role.task_role.id
  policy = data.aws_iam_policy_document.task_role_permissions.json
}

# =============================================================================
# 3. Security group: allow all outbound, deny all inbound (default)
# =============================================================================
resource "aws_security_group" "task" {
  name        = "${var.project}-websocket-relay-sg"
  description = "Websocket relay Fargate task -- outbound only"
  vpc_id      = var.vpc_id

  egress {
    description = "All outbound (WebSocket + AWS APIs)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # No ingress rules -- task doesn't accept inbound.

  tags = { Module = "fargate" }
}

# =============================================================================
# 4. CloudWatch log group for container logs
# =============================================================================
resource "aws_cloudwatch_log_group" "task" {
  name              = "/ecs/${var.project}-websocket-relay"
  retention_in_days = 14
  tags              = { Module = "fargate" }
}

# =============================================================================
# 5. ECS cluster + task definition + service
# =============================================================================
resource "aws_ecs_cluster" "main" {
  name = "${var.project}-cluster"
  setting {
    name  = "containerInsights"
    value = "disabled" # $0.30/GB extra; enable for prod, off for dev
  }
  tags = { Module = "fargate" }
}

resource "aws_ecs_task_definition" "relay" {
  family                   = "${var.project}-websocket-relay"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc" # required for Fargate

  # Smallest supported: 256 CPU units (.25 vCPU) + 512 MB. Enough for our load.
  cpu    = "256"
  memory = "512"

  execution_role_arn = aws_iam_role.task_exec.arn
  task_role_arn      = aws_iam_role.task_role.arn

  container_definitions = jsonencode([{
    name      = "relay"
    image     = "${aws_ecr_repository.websocket_relay.repository_url}:${var.image_tag}"
    essential = true

    environment = [
      { name = "SECRET_ID",           value = var.secret_id_string },
      { name = "TICKERS",             value = var.tickers },
      { name = "KINESIS_STREAM_NAME", value = var.kinesis_stream_name },
      { name = "AWS_REGION",          value = var.aws_region },
    ]

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = aws_cloudwatch_log_group.task.name
        awslogs-region        = var.aws_region
        awslogs-stream-prefix = "relay"
      }
    }

    # Fargate default is SIGTERM then SIGKILL 30s later. Our code flushes on SIGTERM.
    stopTimeout = 30
  }])

  tags = { Module = "fargate" }
}

resource "aws_ecs_service" "relay" {
  name            = "${var.project}-websocket-relay"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.relay.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = var.public_subnet_ids
    security_groups  = [aws_security_group.task.id]
    assign_public_ip = true # cheapest egress: public IP in public subnet, no NAT
  }

  # Minimal deployment config for dev
  deployment_maximum_percent         = 200
  deployment_minimum_healthy_percent = 0

  tags = { Module = "fargate" }
}
