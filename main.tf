terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
} # <--- MAKE SURE THIS BRACE IS HERE!

provider "aws" {
  region     = "us-east-1"
  access_key = "AKIAIOSFODNN7EXAMPLE"
  secret_key = "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"
}

# 1. Random ID Generator (S3 bucket names must be globally unique across all of AWS)
resource "random_id" "bucket_suffix" {
  byte_length = 4
}

# 2. The S3 Bucket (Terraform's Remote Memory)
resource "aws_s3_bucket" "terraform_state" {
  bucket        = "enterprise-cicd-vault-${random_id.bucket_suffix.hex}"
  force_destroy = true # Allows us to easily tear this down later
  
  tags = { Name = "enterprise-cicd-state-vault" }
}

# Explicitly block all public access to the state file vault
resource "aws_s3_bucket_public_access_block" "terraform_state_sec" {
  bucket                  = aws_s3_bucket.terraform_state.id
  
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Enable Versioning (Keeps a backup history of your state file)
resource "aws_s3_bucket_versioning" "state_versioning" {
  bucket = aws_s3_bucket.terraform_state.id
  versioning_configuration {
    status = "Enabled"
  }
}

# Enable Server-Side Encryption (Security best practice)
resource "aws_s3_bucket_server_side_encryption_configuration" "state_encryption" {
  bucket = aws_s3_bucket.terraform_state.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_dynamodb_table" "terraform_locks" {
  name         = "enterprise-cicd-state-locks-${terraform.workspace}" # <--- Added workspace variable
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }
  
  tags = { Name = "enterprise-cicd-state-locks-${terraform.workspace}" }
}
# --- Phase 2: The Container Vault (AWS ECR) ---

resource "aws_ecr_repository" "app_repo" {
  name                 = "enterprise-secure-app-${terraform.workspace}" # <--- Added workspace variable
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true 
  }
}
# --- Phase 3: The Serverless Production Tier (AWS ECS) ---

# 1. IAM Role: Give ECS permission to pull Docker images from your ECR Vault
resource "aws_iam_role" "ecs_execution_role" {
  name = "enterprise-ecs-execution-role-${terraform.workspace}" # <-- Added workspace variable

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
    }]
  })
}

# Attach Amazon's default policy to the role
resource "aws_iam_role_policy_attachment" "ecs_execution_role_policy" {
  role       = aws_iam_role.ecs_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# 2. The Serverless Cluster
resource "aws_ecs_cluster" "app_cluster" {
  name = "enterprise-serverless-cluster-${terraform.workspace}" # <--- Added workspace variable
}

# 3. The Blueprint (Task Definition)
resource "aws_ecs_task_definition" "app_task" {
  family                   = "enterprise-app-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"] # This is the magic "Serverless" keyword!
  cpu                      = "256"       # 0.25 vCPU
  memory                   = "512"       # 0.5 GB RAM
  execution_role_arn       = aws_iam_role.ecs_execution_role.arn

  # This dynamically points to the ECR Vault you built in Phase 2!
  container_definitions = jsonencode([{
    name      = "enterprise-app-container"
    image     = aws_ecr_repository.app_repo.repository_url 
    essential = true
    portMappings = [{
      containerPort = 80
      hostPort      = 80
    }]
  }])
}
# --- Phase 5: The Live Service (Turning it on) ---

# 1. Grab your account's default network
data "aws_vpc" "default" { 
  default = true 
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}
# 3. The Front Door (Security Group)
resource "aws_security_group" "ecs_sg" {
  name        = "enterprise-ecs-sg-${terraform.workspace}" 
  description = "Security group for Enterprise ECS tasks"
  vpc_id      = data.aws_vpc.default.id

  # Failsafe: Restrict inbound traffic to a specific trusted network
  ingress {
    description = "Allow HTTP inbound from corporate VPN/trusted IP only"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["76.139.93.89/32"]
  }

  # Allow HTTPS outbound for AWS APIs and ECR image pulls
  egress {
    description = "Allow HTTPS outbound for AWS APIs and ECR image pulls"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
# 2. The ECS Service (The Engine that runs your container)
resource "aws_ecs_service" "app_service" {
  name            = "enterprise-app-service"
  cluster         = aws_ecs_cluster.app_cluster.id
  task_definition = aws_ecs_task_definition.app_task.arn
  launch_type     = "FARGATE"
  desired_count   = 1 # Run exactly one copy of our container

  network_configuration {
    subnets          = data.aws_subnets.default.ids
    security_groups  = [aws_security_group.ecs_sg.id] # <-- ADD THIS LINE
    assign_public_ip = true
  }
}# Waking up the security scanner
