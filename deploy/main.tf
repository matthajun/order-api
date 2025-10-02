provider "aws" {
  region = "ap-northeast-2"
}

# --- ECS Cluster ---
resource "aws_ecs_cluster" "app_cluster" {
  name = "order-app-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = {
    Name = "order-app-cluster"
  }
}

# --- EC2 Auto Scaling Group (ECS Container Instances) ---
# 기존 VPC ID와 서브넷 ID를 사용하거나, 별도로 생성해야 합니다.
variable "vpc_id" {
  description = "Existing VPC ID"
  type        = string
  default     = "vpc-083e33a4159796273"
}

variable "subnet_ids" {
  description = "List of existing public subnet IDs for ASG"
  type        = list(string)
  default     = ["subnet-0b9e50ed58fa3d6ab", "subnet-027ea6b79ce8879fa"] # 실제 서브넷 ID로 변경
}

# Launch Template for ECS Container Instances
resource "aws_launch_template" "ecs_launch_template" {
  name_prefix   = "ecs-container-instance-"
  image_id      = "ami-0666f25d5f8dcb1db" # Amazon Linux 2 ECS 최신 AMI ID (리전별로 다름, 확인 필요!)
  instance_type = "t3.medium"            # 인스턴스 타입 선택
#   key_name      = "your-ssh-key"         # SSH 접속을 위한 키페어 이름 (선택 사항)

  network_interfaces {
    associate_public_ip_address = true
    security_groups             = [aws_security_group.ecs_instance_sg.id]
  }

  user_data = base64encode(
    # EC2 인스턴스가 시작될 때 ECS 클러스터에 자동으로 등록되도록 설정
    # YOUR_CLUSTER_NAME을 실제 ECS 클러스터 이름으로 변경
    # AWS ECS 최적화 AMI는 /etc/ecs/ecs.config 파일로 설정 가능
    <<EOF
#!/bin/bash
echo ECS_CLUSTER=${aws_ecs_cluster.app_cluster.name} >> /etc/ecs/ecs.config
EOF
  )

  block_device_mappings {
    device_name = "/dev/xvda" # AMI에 따라 다를 수 있음 (lsblk 확인)
    ebs {
      volume_size = 30 # GiB
      volume_type = "gp2"
    }
  }

  iam_instance_profile {
    name = aws_iam_instance_profile.ecs_instance_profile.name
  }

  tags = {
    Name = "ecs-container-instance"
  }
}

# IAM Role for ECS Container Instances
resource "aws_iam_role" "ecs_instance_role" {
  name = "ecs-container-instance-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_instance_role_policy_ec2_container_service_for_ecs" {
  role       = aws_iam_role.ecs_instance_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSTransformApplicationECSDeploymentPolicy"
}

resource "aws_iam_instance_profile" "ecs_instance_profile" {
  name = "ecs-container-instance-profile"
  role = aws_iam_role.ecs_instance_role.name
}

# --- VPC CIDR 블록 변수 ---
variable "vpc_cidr_block" {
  description = "The CIDR block for the existing VPC"
  type        = string
  default     = "10.0.0.0/16" # 실제 VPC CIDR 블록으로 변경
}

# Security Group for ECS Container Instances
resource "aws_security_group" "ecs_instance_sg" {
  name        = "ecs-instance-sg"
  description = "Allow inbound traffic for ECS container instances"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1" # All protocols
    cidr_blocks = [var.vpc_cidr_block] # VPC 내부에서만 접근 허용
  }
  ingress { # ALB로부터의 HTTP/HTTPS 트래픽 허용
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
  }
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
  }
  ingress { # SSH 접속 (선택 사항, 개발/디버깅용)
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # 특정 IP 대역으로 제한하는 것이 좋음
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"] # 모든 아웃바운드 허용
  }

  tags = {
    Name = "ecs-instance-sg"
  }
}

# Auto Scaling Group
resource "aws_autoscaling_group" "ecs_asg" {
  name                      = "ecs-asg-${aws_ecs_cluster.app_cluster.name}"
  vpc_zone_identifier       = var.subnet_ids
  desired_capacity          = 1
  min_size                  = 1
  max_size                  = 3
  launch_template {
    id      = aws_launch_template.ecs_launch_template.id
    version = "$Latest"
  }

  health_check_type         = "EC2"
  health_check_grace_period = 300

  tag {
    key                 = "AmazonECSManaged"
    value               = "true" # ECS Capacity Provider가 관리한다는 의미로 "true" 사용 권장
    propagate_at_launch = true
  }

  tag {
    key                 = "Name"
    value               = "ecs-asg-instance"
    propagate_at_launch = true
  }

  tag {
    key                 = "ecs:cluster-name"
    value               = aws_ecs_cluster.app_cluster.name
    propagate_at_launch = true
  }
}

# --- ECS Capacity Provider (ASG와 클러스터 연결) ---
resource "aws_ecs_capacity_provider" "app_capacity_provider" {
  name = "order-app-capacity-provider"

  auto_scaling_group_provider {
    auto_scaling_group_arn         = aws_autoscaling_group.ecs_asg.arn
    managed_scaling {
      status          = "ENABLED"
      target_capacity = 70 # ECS가 ASG 인스턴스의 70%를 유지하도록 시도
      # max_scaling_step_size = 100
      # min_scaling_step_size = 1
    }
    managed_termination_protection = "DISABLED" # ECS가 컨테이너를 실행 중인 인스턴스를 보호
  }
}

resource "aws_ecs_cluster_capacity_providers" "app_cluster_providers" {
  cluster_name       = aws_ecs_cluster.app_cluster.name
  capacity_providers = [aws_ecs_capacity_provider.app_capacity_provider.name]

  default_capacity_provider_strategy {
    capacity_provider = aws_ecs_capacity_provider.app_capacity_provider.name
    weight            = 1
    base              = 1 # 최소 1개의 태스크는 이 캐패시티 프로바이더에서 실행
  }
}

# --- Application Load Balancer (ALB) ---
resource "aws_lb" "app_alb" {
  name               = "order-app-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = var.subnet_ids

  tags = {
    Name = "order-app-alb"
  }
}

resource "aws_lb_target_group" "app_tg" {
  name        = "my-app-tg"
  port        = 3000
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  tags = {
    Name = "my-app-tg"
  }
}

resource "aws_lb_listener" "http_listener" {
  load_balancer_arn = aws_lb.app_alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app_tg.arn
  }

  depends_on = [
      aws_lb_target_group.app_tg
  ]
}

# Security Group for ALB (외부에서 접근 허용)
resource "aws_security_group" "alb_sg" {
  name        = "alb-sg"
  description = "Allow HTTP/HTTPS traffic to ALB"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # 외부에서 HTTP 접근 허용
  }
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # 외부에서 HTTPS 접근 허용 (SSL 인증서 필요)
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "alb-sg"
  }
}

# --- ECS Task Definition ---
# ECR Repository ARN
variable "ecr_repository_url" {
  description = "URL of the ECR repository for the application image"
  type        = string
  default     = "586253722217.dkr.ecr.ap-northeast-2.amazonaws.com/order-app"
}

resource "aws_ecs_task_definition" "app_task" {
  family                   = "order-app-task"
  network_mode             = "awsvpc"
  cpu                      = "256"
  memory                   = "512"
  requires_compatibilities = ["EC2"]
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn
  task_role_arn            = aws_iam_role.ecs_task_role.arn

  container_definitions = jsonencode([
    {
      name        = "order-app-api"
      image       = var.ecr_repository_url # ECR 이미지 URL
      cpu         = 256
      memory      = 512
      essential   = true
      portMappings = [
        {
          containerPort = 3000
          hostPort      = 3000
          protocol      = "tcp"
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.app_log_group.name
          "awslogs-region"        = "ap-northeast-2"
          "awslogs-stream-prefix" = "ecs"
        }
      }
      environment = [ # 환경 변수 예시
        {
          name  = "DATABASE_URL"
          value = "file:./prisma/order.db"
        }
      ]
    }
  ])

  tags = {
    Name = "order-app-task"
  }
}

# IAM Role for ECS Task Execution (컨테이너 이미지 가져오기, 로그 전송 등)
resource "aws_iam_role" "ecs_task_execution_role" {
  name = "ecs-task-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution_role_policy_ecs_task_execution_role" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# IAM Role for ECS Task (컨테이너 내부에서 AWS 서비스 접근 시)
resource "aws_iam_role" "ecs_task_role" {
  name = "ecs-task-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      },
    ]
  })
}

# CloudWatch Log Group for ECS Task Logs
resource "aws_cloudwatch_log_group" "app_log_group" {
  name              = "/ecs/order-app"
  retention_in_days = 7 # 로그 보존 기간

  tags = {
    Name = "order-app-log-group"
  }
}


# --- ECS Service ---
resource "aws_ecs_service" "app_service" {
  name            = "order-app-service"
  cluster         = aws_ecs_cluster.app_cluster.id
  task_definition = aws_ecs_task_definition.app_task.arn
  desired_count   = 1
#   launch_type     = "EC2" # EC2 기반 서비스

  capacity_provider_strategy {
    capacity_provider = aws_ecs_capacity_provider.app_capacity_provider.name
    weight            = 1
    base              = 1
  }

  deployment_controller {
    type = "ECS" # ECS 기본 배포 컨트롤러
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.app_tg.arn
    container_name   = "order-app-api"
    container_port   = 3000
  }

  network_configuration {
    subnets          = var.subnet_ids
    security_groups  = [aws_security_group.ecs_instance_sg.id]
    assign_public_ip = false
  }


  lifecycle {
    ignore_changes = [desired_count]
  }

  tags = {
    Name = "order-app-service"
  }

  depends_on = [
      aws_lb_listener.http_listener,
      aws_lb_target_group.app_tg
  ]
}

# --- ECS Service Auto Scaling Policy (태스크 수 조절) ---
resource "aws_appautoscaling_target" "ecs_task_scaling_target" {
  max_capacity       = 2 # 서비스의 최대 태스크 수
  min_capacity       = 1 # 서비스의 최소 태스크 수
  resource_id        = "service/${aws_ecs_cluster.app_cluster.name}/${aws_ecs_service.app_service.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

resource "aws_appautoscaling_policy" "ecs_task_cpu_scaling_policy" {
  name               = "ecs-task-cpu-scaling-policy"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.ecs_task_scaling_target.resource_id
  scalable_dimension = aws_appautoscaling_target.ecs_task_scaling_target.scalable_dimension
  service_namespace  = aws_appautoscaling_target.ecs_task_scaling_target.service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization" # 평균 CPU 사용률
    }
    target_value = 50.0 # 평균 CPU 사용률 50%를 목표로 스케일링
    scale_in_cooldown  = 300 # 스케일 인 후 5분 동안 스케일 인 방지
    scale_out_cooldown = 300 # 스케일 아웃 후 5분 동안 스케일 아웃 방지
  }
}

# --- Outputs ---
output "alb_dns_name" {
  description = "The DNS name of the Application Load Balancer"
  value       = aws_lb.app_alb.dns_name
}

output "ecs_cluster_name" {
  description = "The name of the ECS cluster"
  value       = aws_ecs_cluster.app_cluster.name
}

resource "aws_route53_zone" "main" {
  name = "matthajun.com"
}

resource "aws_route53_record" "app_domain_record" {
  zone_id = aws_route53_zone.main.zone_id
  name    = "alb.matthajun.com"
  type    = "A"

  alias {
    name                   = aws_lb.app_alb.dns_name
    zone_id                = aws_lb.app_alb.zone_id
    evaluate_target_health = false
  }
}

resource "aws_security_group" "app_sg" {
  name_prefix = "app-sg-"
  vpc_id      = var.vpc_id

  ingress { # ALB 보안 그룹으로부터 컨테이너 포트 인바운드 허용
    from_port       = 3000
    to_port         = 3000
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id] # ALB SG ID
    description     = "Allow traffic from ALB"
  }
  egress { # 태스크는 외부 리소스 (예: ECR, CloudWatch Logs, DB 등) 접근을 위해 아웃바운드 허용
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}