    provider "aws" {
        region = "us-east-2"
}


    resource "aws_instance" "swarmp" {
        ami     = "ami-0c55b159cbfafe1f0"
        instance_type = "t2.micro"
        vpc_security_group_ids = [aws_security_group.instance.id]

        user_data = <<-EOF
                    #!/bin/bash
                    echo "Hello, World" > index.html
                    nohup busybox httpd -f -p ${var.server_port} &
                    EOF

        tags = {
        Name = "swarmp_instance"
    }

}

/*
    variable "server_port" {
        description = "The port the server will use for HTTP requests"
        type = number
        default = 8080
    }
*/

    resource "aws_security_group" "instance" {
        name = "terraform-swarmp-instance"

    ingress {
        from_port = var.server_port
        to_port = var.server_port
        protocol = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }
  
}

    output "public_ip" {
      value = aws_instance.swarmp.public_ip
      description = "The public IP address of the web server"
    }



# Auto Scaling Group 

    resource "aws_launch_configuration" "swarmp-asg" {
      image_id = "ami-0c55b159cbfafe1f0"
      instance_type = "t2.micro"
      security_groups = [aws_security_group.instance.id]

      user_data = <<-EOF
                    #!/bin/bash
                    echo "Hello, World" > index.html
                    nohup busybox httpd -f -p ${var.server_port} & 
                    EOF

    # Required when using a launch configuration with an auto scaling group.
    # https://www.terraform.io/docs/providers/aws/r/launch_configuration.html

    lifecycle {
        create_before_destroy = true
    }
}

terraform {
    backend "s3" {
        bucket = "amfilling"
        region = "us-east-2"
        dynamodb_table = "filling-up-locks"
        encrypt = true
        key = "global/s3/terraform.tfstate"
    }
}

    resource "aws_security_group" "alb" {
      name = "terraform-swarmp-asg-alb"

    # Allow inbound HTTP requests
    ingress {
        from_port = 80
        to_port = 80
        protocol = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }  

    # Allow all outbound requests
    egress {
        from_port = 0
        to_port = 0
        protocol = "-1"
        cidr_blocks = ["0.0.0.0/0"]
    }
}


     variable "server_port" {
        description = "The port the server will use for HTTP requests"
        type = number
        default = 8080
}

    resource "aws_autoscaling_group" "swarmp-asg" {
      launch_configuration = aws_launch_configuration.swarmp-asg.name
      vpc_zone_identifier = data.aws_subnets.default.ids

      target_group_arns = [aws_lb_target_group.asg.arn]
      health_check_type = "ELB"

      min_size = 2
      max_size = 10

      tag {
        key = "Name"
        value = "terraform-asg-swarmp-asg"
        propagate_at_launch = true
      }
}

    data "aws_vpc" "default" {
      default = true
}
    data "aws_subnets" "default" {
    filter {
        name   = "vpc-id"
        values = [data.aws_vpc.default.id]
  }

}


    resource "aws_lb" "swarmp-asg" {
        name = "terraform-asg-swarmp-asg"
        load_balancer_type = "application"
        subnets = data.aws_subnets.default.ids
        security_groups = [aws_security_group.alb.id]
}

    resource "aws_lb_target_group" "asg" {
        name = "terraform-asg-swarmp-asg"
        port = var.server_port
        protocol = "HTTP"
        vpc_id = data.aws_vpc.default.id

        health_check {
          path = "/"
          protocol = "HTTP"
          matcher = "200"
          interval = 15
          timeout = 3
          healthy_threshold = 2
          unhealthy_threshold = 2
        }
    }

    resource "aws_lb_listener_rule" "static" {
        listener_arn = aws_lb_listener.http.arn
        priority = 100
      
        condition {
            path_pattern {
            values = ["/static/*"] 
            }
        }   
        action {
          type = "forward"
          target_group_arn = aws_lb_target_group.asg.arn
        }
}

    resource "aws_lb_listener" "http" {
        load_balancer_arn = aws_lb.swarmp-asg.arn
        port = 80
        protocol = "HTTP"

    # By default, return a simple 404 page
    default_action {
      type = "fixed-response"

    fixed_response {
        content_type = "text/plain"
        message_body = "404: page not found"
        status_code = 404
        }
    }     
}

    output "alb_dns_name" {
        value = aws_lb.swarmp-asg.dns_name
        description = "The domain name of the load balancer"
}