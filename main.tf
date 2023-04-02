provider "aws" {
  region = "us-east-1"
}

resource "aws_ecr_repository" "fiap-repository" {
  name                 = "fiap-hackaton"
  image_tag_mutability = "MUTABLE"
}

resource "aws_cloudwatch_log_group" "ecs_logs" {
  name = "/ecs/ecs-cluster-fiap"
}

resource "aws_iam_policy" "ecs_logs_policy" {
  name_prefix = "ecs_logs_policy"
  policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ],
      "Effect": "Allow",
      "Resource": "${aws_cloudwatch_log_group.ecs_logs.arn}:*"
    }
  ]
}
POLICY
}

resource "aws_iam_role" "ecs_task_role" {
  name = "ecs_task_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_task_role_attachment" {
  policy_arn = aws_iam_policy.ecs_logs_policy.arn
  role       = aws_iam_role.ecs_task_role.name
}


resource "aws_ecr_repository_policy" "fiap-repo-policy" {
  repository = aws_ecr_repository.fiap-repository.name
  policy     = <<EOF
  {
    "Version": "2008-10-17",
    "Statement": [
      {
        "Sid": "adds full ecr access to the fiap repository",
        "Effect": "Allow",
        "Principal": "*",
        "Action": [
          "ecr:BatchCheckLayerAvailability",
          "ecr:BatchGetImage",
          "ecr:CompleteLayerUpload",
          "ecr:GetDownloadUrlForLayer",
          "ecr:GetLifecyclePolicy",
          "ecr:InitiateLayerUpload",
          "ecr:PutImage",
          "ecr:UploadLayerPart"
        ]
      }
    ]
  }
  EOF
}

resource "aws_ecs_cluster" "fiap-ecs-cluster" {
  name = "ecs-cluster-fiap"
}

resource "aws_iam_role" "ecs_task_execution_role" {
  name = "ecsTaskExecutionRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution_role_policy" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
  role       = aws_iam_role.ecs_task_execution_role.name
}

resource "aws_ecs_service" "fiap-ecs-service-two" {
  name            = "fiap-hackaton"
  cluster         = aws_ecs_cluster.fiap-ecs-cluster.id
  task_definition = aws_ecs_task_definition.fiap-ecs-task-definition.arn
  launch_type     = "FARGATE"
  network_configuration {
    subnets          = ["subnet-0b54b3ef770de5caa"]
    assign_public_ip = true
  }
  desired_count = 1
}

resource "aws_ecs_task_definition" "fiap-ecs-task-definition" {
  family                   = "ecs-task-definition-fiap"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  memory                   = "2048"
  cpu                      = "1024"
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn
  task_role_arn            = aws_iam_role.ecs_task_execution_role.arn
  container_definitions    = <<EOF
[
  {
    "name": "fiap-hackaton",
    "image": "117369304772.dkr.ecr.us-east-1.amazonaws.com/fiap-hackaton:71f1baeaa80b642bc9c2717badfea765e2255cee",
    "memory": 2048,
    "cpu": 1024,
    "essential": true,
    "entryPoint": ["java","-Dspring.profiles.active=prod","-Djava.security.egd=file:/dev/./urandom","-jar","/home/gradle/project/app.jar"],
    "portMappings": [
      {
        "containerPort": 80,
        "hostPort": 80
      }
    ],
    "logConfiguration": {
      "logDriver": "awslogs",
      "options": {
        "awslogs-group": "/ecs/ecs-cluster-fiap",
        "awslogs-region": "us-east-1",
        "awslogs-stream-prefix": "ecs-cluster-fiap"
      }
    }
  }
]
EOF
}
