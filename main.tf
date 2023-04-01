provider "aws" {
  region = "us-east-1"
}

resource "aws_ecs_cluster" "hackaton_fiap" {
  name = "hackaton_fiap-cluster"
}

resource "aws_ecr_repository" "hackaton_fiap" {
  name = "hackaton_fiap-repo"
}

resource "aws_ecs_task_definition" "hackaton_fiap" {
  family                   = "hackaton_fiap-task"
  container_definitions    = jsonencode([
    {
      name  = "hackathon-fiap-container"
      image = "${aws_ecr_repository.hackaton_fiap.repository_url}:latest"
      port_mappings = {
        container_port = 8080
      }
      environment = [
        { name = "DB_HOSTNAME", value = var.db_hostname },
        { name = "DB_PORT", value = var.db_port },
        { name = "DB_NAME", value = var.db_name },
        { name = "DB_USERNAME", value = var.db_username },
        { name = "DB_PASSWORD", value = var.db_password },
      ]
    }
  ])
  memory                   = "512"
  cpu                      = "256"
}

resource "aws_ecs_service" "hackaton_fiap" {
  name            = "hackaton_fiap-service"
  cluster         = aws_ecs_cluster.hackaton_fiap.id
  task_definition = aws_ecs_task_definition.hackaton_fiap.arn
  desired_count   = 1

  deployment_controller {
    type = "ECS"
  }
}

output "service_url" {
  value = "http://${aws_ecs_service.hackaton_fiap.name}.${aws_ecs_cluster.hackaton_fiap.id}.us-east-1.amazonaws.com"
}
