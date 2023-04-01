provider "aws" {
  region = "us-east-1"
}

# Define a variável de entrada
variable "image_name" {
  default = "hackaton_fiap-repo"
}

resource "aws_iam_role" "ecs_instance_role" {
  name = "ecs_instance_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  inline_policy {
    name = "ecs_instance_policy"

    policy = jsonencode({
      Version = "2012-10-17",
      Statement = [
        {
          Effect = "Allow",
          Action = [
            "ecs:CreateCluster",
            "ecs:DeregisterContainerInstance",
            "ecs:DiscoverPollEndpoint",
            "ecs:Poll",
            "ecs:RegisterContainerInstance",
            "ecs:StartTelemetrySession",
            "ecs:Submit*",
            "ecr:GetAuthorizationToken",
            "ecr:BatchCheckLayerAvailability",
            "ecr:GetDownloadUrlForLayer",
            "ecr:GetRepositoryPolicy",
            "ecr:DescribeRepositories",
            "ecr:ListImages",
            "ecr:BatchGetImage",
            "logs:CreateLogStream",
            "logs:PutLogEvents"
          ],
          Resource = "*"
        }
      ]
    })
  }
}

# Cria uma função IAM para as instâncias do EC2 para permitir que sejam gerenciadas pelo ECS
resource "aws_iam_role" "ecs_instance_role" {
  name = "ecs_instance_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

# Anexa uma política IAM à função do ECS para permitir que as instâncias do EC2 sejam gerenciadas pelo ECS
resource "aws_iam_role_policy_attachment" "ecs_instance_policy_attachment" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
  role       = aws_iam_role.ecs_instance_role.name
}


# Cria a política de permissão do ECS para acessar o ECR
resource "aws_ecs_task_definition" "fiap_deploy_task" {
  family                   = "fiap_deploy_task"
  container_definitions    = jsonencode([
    {
      name  = "fiap_container"
      image = "${aws_ecr_repository.fiap_repository.repository_url}:${var.image_name}"
      portMappings = [
        {
          containerPort = 80
          hostPort      = 80
        }
      ]
    }
  ])
  requires_compatibilities = ["FARGATE"]
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn
  task_role_arn            = aws_iam_role.ecs_task_execution_role.arn
}

# Cria a política de permissão do EC2 para acessar o ECS
resource "aws_iam_role" "ecs_task_execution_role" {
  name = "ecs_task_execution_role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution_role_attachment" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
  role       = aws_iam_role.ecs_task_execution_role.name
}

# Cria o Launch Configuration
resource "aws_launch_configuration" "ec2_fiap_launch_config" {
  image_id        = "ami-0c55b159cbfafe1f0"
  instance_type  = "t2.micro"
  security_groups = ["${aws_security_group.ec2_sg.id}"]
  iam_instance_profile = aws_iam_instance_profile.ec2_profile.id

  lifecycle {
    create_before_destroy = true
  }

  user_data = <<-EOF
              #!/bin/bash
              echo ECS_CLUSTER=${aws_ecs_cluster.fiap_cluster.name} >> /etc/ecs/ecs.config
              EOF
}

# Cria o Auto Scaling Group
resource "aws_autoscaling_group" "fiap_asg" {
  name                 = "fiap_asg"
  launch_configuration = aws_launch_configuration.ec2_fiap_launch_config.id
  min_size             = 1
  max_size             = 1
  desired_capacity     = 1
  vpc_zone_identifier  = ["${aws_subnet.fiap_backend_subnet.id}"]
}

# Cria a instância do EC2
resource "aws_instance" "fiap_instance" {
  ami           = "ami-0c55b159cbfafe1f0"
  instance_type = "t2.micro"
  subnet_id     = aws_subnet.fiap_backend_subnet.id
  security_groups = ["${aws_security_group.ec2_sg.id}"]
  iam_instance_profile = aws_iam_instance_profile.ec2_profile.id

  lifecycle {
    create_before_destroy = true
  }

  user_data = <<-EOF
  #!/bin/bash
  echo ECS_CLUSTER=${aws_ecs_cluster.fiap_cluster.name} >> /etc/ecs/ecs.config
  EOF
}

# Cria a definição do Serviço ECS
resource "aws_ecs_service" "fiap_deploy_service" {
  name = "fiap_deploy_service"
  cluster = aws_ecs_cluster.fiap_cluster.id
  task_definition = aws_ecs_task_definition.fiap_deploy_task.arn
  launch_type = "FARGATE"

  network_configuration {
    security_groups = ["${aws_security_group.ecs_sg.id}"]
    subnets = ["${aws_subnet.fiap_backend_subnet.id}"]
  }
}

# Cria a regra do EventBridge para disparar o pipeline
resource "aws_cloudwatch_event_rule" "fiap_cloudwatch_rule" {
name = "fiap_cloudwatch_rule"
description = "Rule to trigger pipeline on ECR push"

event_pattern = jsonencode({
source = ["aws.ecr"]
detail-type = ["ECR Image Action"]
detail = {
action = ["push"]
repository-name = ["fiap_repository"]
}
})
}

#Cria o alvo da regra do EventBridge para chamar o ECS
resource "aws_cloudwatch_event_target" "ecs_fiap_target" {
  rule = aws_cloudwatch_event_rule.fiap_cloudwatch_rule.name
  arn = aws_ecs_cluster.fiap_cluster.arn
  role_arn = aws_iam_role.ecs_task_execution_role.arn
  input = jsonencode({
    containerOverrides = [
      {
        name = "fiap_container"
        environment = [
          {
          name = "IMAGE_TAG"
          value = "$$.detail.image-tags[0]"
          }
          ]
      }
    ]
  })
}

# Cria os grupos de segurança do EC2 e ECS
resource "aws_security_group" "ec2_sg" {
  name_prefix = "fiap-ec2-sg"
  vpc_id = "vpc-12345"

  ingress {
    from_port = 80
    to_port = 80
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

egress {
  from_port = 0
  to_port = 0
  protocol = "-1"
  cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "ecs_sg" {
  name_prefix = "fiap-ecs-sg"
  vpc_id = "vpc-07a421d637fa328fc"

  ingress {
  from_port = 80
  to_port = 80
  protocol = "tcp"
  security_groups = [aws_security_group.ec2_sg.id]
  }

  egress {
  from_port = 0
  to_port = 0
  protocol = "-1"
  cidr_blocks = ["0.0.0.0/0"]
  }
}

# Cria um perfil de instância EC2 para permitir que as instâncias do EC2 possam se registrar no cluster ECS
resource "aws_iam_instance_profile" "ec2_profile" {
  name = "ec2_profile"

  role {
    name = aws_iam_role.ecs_instance_role.name
  }
}

# Cria um repositório do ECR para armazenar a imagem da aplicação
resource "aws_ecr_repository" "fiap_repository" {
  name = "fiap_repository"
}


#Cria a subrede do EC2
resource "aws_subnet" "fiap_backend_subnet" {
  vpc_id = "vpc-07a421d637fa328fc"
  cidr_block = "10.0.0.0/24"
  availability_zone = "us-east-1a"
}

#Cria o cluster ECS
resource "aws_ecs_cluster" "fiap_cluster" {
  name = "fiap_cluster"
}