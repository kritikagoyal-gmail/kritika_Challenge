# Provider
terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
  }
}

## Create VPC
resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
  tags = {
    Name = "my-vpc"
  }
}

## Read Availabilty ZOnes
data "aws_availability_zones" "available" {}

## Create public subnet in each availability zone
resource "aws_subnet" "public_subnet" {
  count = "${length(data.aws_availability_zones.available.names)}"
  vpc_id = "${aws_vpc.main.id}"
  cidr_block = "10.0.${10+count.index}.0/24"
  availability_zone = "${data.aws_availability_zones.available.names[count.index]}"
  map_public_ip_on_launch = false
  tags = {
    Name = "My_PublicSubnet-${count.index}"
  }
}

# Create internet gateway
resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "main"
  }
}

resource "aws_route_table" "eks_igw_route" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }

  tags = {
    Name = "my_igw_route"
  }
}

## Associating Internet gateway with subnets
resource "aws_route_table_association" "route_public" {
  count = "${length(aws_subnet.public_subnet)}"
  subnet_id      = aws_subnet.public_subnet[count.index].id
  route_table_id = aws_route_table.eks_igw_route.id
}

## Security gorup for Ec2 instances
resource "aws_security_group" "instance-sg" {
  vpc_id      = aws_vpc.main.id
  name = "instance-sg"
  ingress {
    from_port = 80
    to_port = 80
    protocol = "tcp"
    security_groups = ["${aws_security_group.elb.id}"]
  }

#  ingress {
#    from_port = 22
#    to_port = 22
#    protocol = "tcp"
#    cidr_blocks = ["0.0.0.0/0"]
#  }

  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

}

## Launch template
resource "aws_launch_template" "my_template" {
  name_prefix   = "my_template"
  image_id      = var.ami  # ubuntu AMI
  instance_type = "t2.micro"

  network_interfaces {
    associate_public_ip_address = true
    security_groups = ["${aws_security_group.instance-sg.id}"]
  }
  user_data = filebase64("${path.module}/static-web.sh")

}

## Auto Scaling group
resource "aws_autoscaling_group" "my_asg" {
  desired_capacity   = 2
  max_size           = 3
  min_size           = 2
  vpc_zone_identifier = aws_subnet.public_subnet[*].id
  target_group_arns = ["${aws_alb_target_group.group.arn}"]

  launch_template {
    id      = aws_launch_template.my_template.id
    version = "$Latest"
  }
}

## Security Group for ELB
resource "aws_security_group" "elb" {
  name = "terraform-example-elb"
  vpc_id  = aws_vpc.main.id
  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port = 80
    to_port = 80
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port = 443
    to_port = 443
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

## Creating ELB
resource "aws_lb" "my_lb" {
  name               = "my-lb"
  internal           = true
  load_balancer_type = "application"
  security_groups    = [aws_security_group.elb.id]
  subnets            = [for subnet in aws_subnet.public_subnet : subnet.id]

  enable_deletion_protection = false

  tags = {
    Environment = "production"
  }
}

resource "aws_alb_target_group" "group" {
  name     = "terraform-example-alb-target"
  port     = 80
  protocol = "HTTP"
  vpc_id   = "${aws_vpc.main.id}"
  stickiness {
    type = "lb_cookie"
  }
  # Alter the destination of the health check to be the login page.
  health_check {
    path = "/"
    port = 80
  }
}


resource "aws_alb_listener" "listener_https" {
  load_balancer_arn = "${aws_lb.my_lb.arn}"
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-2016-08"
  certificate_arn   = aws_acm_certificate.cert.arn 

  default_action {
    target_group_arn = "${aws_alb_target_group.group.arn}"
    type             = "forward"
  }
}

resource "aws_lb_listener" "listener_http" {
  load_balancer_arn = aws_lb.my_lb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type = "redirect"

    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

resource "aws_lb_listener_certificate" "listener_cert" {
  listener_arn    = aws_alb_listener.listener_https.arn
  certificate_arn = aws_acm_certificate.cert.arn
}

## Reading hosted Zone data
data "aws_route53_zone" "primary" {
  name = var.hosted-zone
}

## Generate Certificates
resource "aws_acm_certificate" "cert" {
  domain_name       = var.site-address
  validation_method = "DNS"
}

## Alias for ELB in route 53
resource "aws_route53_record" "www" {
  zone_id = data.aws_route53_zone.primary.zone_id
  name    = var.site-address
  type    = "A"

  alias {
    name                   = aws_lb.my_lb.dns_name
    zone_id                = aws_lb.my_lb.zone_id
    evaluate_target_health = true
  }
}

## Certificate validation
resource "aws_route53_record" "validation" {
  name    = "${tolist(aws_acm_certificate.cert.domain_validation_options)[0].resource_record_name}"
  type    = "${tolist(aws_acm_certificate.cert.domain_validation_options)[0].resource_record_type}"
  zone_id = "${data.aws_route53_zone.primary.zone_id}"
  records = ["${tolist(aws_acm_certificate.cert.domain_validation_options)[0].resource_record_value}"]
  ttl     = "60"
}
