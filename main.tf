terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
} # <--- MAKE SURE THIS BRACE IS HERE!

provider "aws" {
  region = "us-east-1"
}

# 1. Random ID Generator (S3 bucket names must be globally unique across all of AWS)
resource "random_id" "bucket_suffix" {
  byte_length = 4
}

# 2. The S3 Bucket (Terraform's Remote Memory)
resource "aws_s3_bucket" "terraform_state" # Explicitly block all public access to the state file vault
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

# 3. The DynamoDB Table (The State Lock)
resource "aws_dynamodb_table" "terraform_locks" {
  name         = "enterprise-cicd-state-locks"
  billing_mode = "PAY_PER_REQUEST" # Free-tier friendly, only pay for what you use
  hash_key     = "LockID"          # Terraform specifically looks for this exact key name

  attribute {
    name = "LockID"
    type = "S"
  }
  
  tags = { Name = "enterprise-cicd-state-locks" }
}
# --- Phase 2: The Container Vault (AWS ECR) ---

resource "aws_ecr_repository" "app_repo" {
  name                 = "enterprise-secure-app"
  image_tag_mutability = "MUTABLE"
  force_delete         = true # Allows clean teardown later

  # This is a massive resume booster: AWS will automatically scan your code for vulnerabilities
  image_scanning_configuration {
    scan_on_push = true 
  }
}
# --- Phase 3: The Serverless Production Tier (AWS ECS) ---

# 1. IAM Role: Give ECS permission to pull Docker images from your ECR Vault
resource "aws_iam_role" "ecs_execution_role" {
  name = "enterprise-ecs-execution-role"
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
  name = "enterprise-serverless-cluster"
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
  name        = "enterprise-ecs-sg"
  description = "Security group for Enterprise ECS tasks"
  vpc_id      = data.aws_vpc.default.id

  # Failsafe: Restrict inbound traffic to a specific trusted network
  ingress {
    description = "Allow HTTP inbound from corporate VPN/trusted IP only"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    # For a real client, this would be their corporate office IP. 
    # For your portfolio, put your actual public IP address here (e.g., "203.0.113.50/32")
    cidr_blocks = ["76.139.93.89/32"] 
  }

  # Failsafe: Restrict outbound traffic to HTTPS only (No more "Port -1")
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
}