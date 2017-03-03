#provider "aws" {
#  access_key = ""
#  secret_key = ""
#  region     = "us-west-2"
#}

# AWS IAM config

resource "aws_key_pair" "ecs_ssh_key" {
  key_name   = "ecs-ssh-key"
  public_key = "${file("ecs-ssh-key.txt")}"
}


resource "aws_iam_role" "ecs_instance_role" {
  name = "ecs-instance-role"
  assume_role_policy = "${file("ecs-role.json")}"
}

# http://docs.aws.amazon.com/AmazonECS/latest/developerguide/instance_IAM_role.html
resource "aws_iam_role_policy" "ecs_instance_role_policy" {
  name = "ecs-instance-role-policy"
  policy = "${file("ecs-instance-role-policy.json")}"
  role = "${aws_iam_role.ecs_instance_role.id}"
}


resource "aws_iam_role" "ecs_service_role" {
  name = "ecs-service-role"
  assume_role_policy = "${file("ecs-role.json")}"
}

# http://docs.aws.amazon.com/AmazonECS/latest/developerguide/service_IAM_role.html
resource "aws_iam_role_policy" "ecs_service_role_policy" {
  name = "ecs-service-role-policy"
  policy = "${file("ecs-service-role-policy.json")}"
  role = "${aws_iam_role.ecs_service_role.id}"
}

resource "aws_iam_role" "ecs_service_task_role" {
  name = "ecs-service-task-role"
  assume_role_policy = "${file("ecs-role.json")}"
}

resource "aws_iam_role" "ecs_autoscale_role" {
  name = "ecs-autoscale-role"
  assume_role_policy = "${file("ecs-role.json")}"
}

# http://docs.aws.amazon.com/AmazonECS/latest/developerguide/service-auto-scaling.html
resource "aws_iam_role_policy" "ecs_autoscale_role_policy" {
  name = "ecs-autoscale-role-policy"
  policy = "${file("ecs-autoscale-role-policy.json")}"
  role = "${aws_iam_role.ecs_autoscale_role.id}"
}


resource "aws_iam_instance_profile" "ecs" {
  name = "ecs-instance-profile"
  path = "/"
  roles = ["${aws_iam_role.ecs_instance_role.name}"]
}


# AWS Networking (VPC, Subnet, Gateway, etc) 

resource "aws_vpc" "ecs_main" {
  cidr_block = "10.0.0.0/16"
  enable_dns_hostnames = true
}


resource "aws_internet_gateway" "ecs_main" {
  vpc_id = "${aws_vpc.ecs_main.id}"
}


resource "aws_route_table" "ecs_main_rt_external" {
  vpc_id = "${aws_vpc.ecs_main.id}"
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = "${aws_internet_gateway.ecs_main.id}"
  }
}


resource "aws_subnet" "ecs_main_us_west_2a" {
  vpc_id = "${aws_vpc.ecs_main.id}"
  cidr_block = "10.0.1.0/24"
  availability_zone = "us-west-2a"
}

resource "aws_subnet" "ecs_main_us_west_2b" {
  vpc_id = "${aws_vpc.ecs_main.id}"
  cidr_block = "10.0.2.0/24"
  availability_zone = "us-west-2b"
}

resource "aws_subnet" "ecs_main_us_west_2c" {
  vpc_id = "${aws_vpc.ecs_main.id}"
  cidr_block = "10.0.3.0/24"
  availability_zone = "us-west-2c"
}


resource "aws_route_table_association" "ecs_main_rt_external_us_west-2a" {
  subnet_id = "${aws_subnet.ecs_main_us_west_2a.id}"
  route_table_id = "${aws_route_table.ecs_main_rt_external.id}"
}

resource "aws_route_table_association" "ecs_main_rt_external_us_west-2b" {
  subnet_id = "${aws_subnet.ecs_main_us_west_2b.id}"
  route_table_id = "${aws_route_table.ecs_main_rt_external.id}"
}

resource "aws_route_table_association" "ecs_main_rt_external_us_west-2c" {
  subnet_id = "${aws_subnet.ecs_main_us_west_2c.id}"
  route_table_id = "${aws_route_table.ecs_main_rt_external.id}"
}

# AWS Security Group

resource "aws_security_group" "ecs_lb" {
  name = "ecs-lb"
  description = "Internet facing, allow all traffic"
  vpc_id = "${aws_vpc.ecs_main.id}"

  ingress {
    from_port = 80
    to_port = 8080
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


resource "aws_security_group" "ecs_instances" {
  name = "ecs-instances"
  description = "EC2 instance sec group"
  vpc_id = "${aws_vpc.ecs_main.id}"

  # This is for testing to be able to SSH into the box easily
  ingress {
    from_port = 22
    to_port = 22
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port = 0
    to_port = 65535
    protocol = "tcp"
    security_groups = ["${aws_security_group.ecs_lb.id}"]
  }

  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# AWS ECS auto-scale and launch

resource "aws_launch_configuration" "ecs_main_cluster_launch" {
    name = "ECS Main"
    image_id = "ami-022b9262"
    instance_type = "t2.small"
    security_groups = ["${aws_security_group.ecs_instances.id}"]
    iam_instance_profile = "${aws_iam_instance_profile.ecs.name}"
    key_name = "${aws_key_pair.ecs_ssh_key.key_name}"
    associate_public_ip_address = true
    user_data = "#!/bin/bash\necho ECS_CLUSTER=${aws_ecs_cluster.ecs_main.name} > /etc/ecs/ecs.config"
}

resource "aws_autoscaling_group" "ecs_main_cluster" {
  availability_zones = ["us-west-2a", "us-west-2b", "us-west-2c"]
  name = "ECS Main"
  min_size = "1"
  max_size = "3"
  desired_capacity = "2"
  health_check_type = "EC2"
  launch_configuration = "${aws_launch_configuration.ecs_main_cluster_launch.name}"
  vpc_zone_identifier = ["${aws_subnet.ecs_main_us_west_2a.id}", "${aws_subnet.ecs_main_us_west_2b.id}", "${aws_subnet.ecs_main_us_west_2c.id}"]
}


# AWS ECS, Service and Task Definitions

resource "aws_ecs_cluster" "ecs_main" {
  name = "Main"
}

resource "aws_ecs_task_definition" "ecs_main_node_simple_app" {
  family = "ecs-main-node-simple-app"
  container_definitions = "${file("ecs-main-node-simple-app-task-def.json")}"
}

resource "aws_ecs_service" "ecs_main_node_service" {
  name = "ecs-main-node-service"
  cluster = "${aws_ecs_cluster.ecs_main.id}"
  task_definition = "${aws_ecs_task_definition.ecs_main_node_simple_app.arn}"
  iam_role = "${aws_iam_role.ecs_service_role.arn}"
  desired_count = 2
  depends_on = ["aws_iam_role_policy.ecs_service_role_policy"]

  load_balancer {
    elb_name = "ecs-main-node-service-elb"
    container_name = "ecs-main-node-service-container"
    container_port = 8080
  }
}


# AWS ELB/ALB

resource "aws_elb" "ecs_main_node_service_elb" {
  name = "ecs-main-node-service-elb"
  security_groups = ["${aws_security_group.ecs_lb.id}"]
  subnets = ["${aws_subnet.ecs_main_us_west_2a.id}", "${aws_subnet.ecs_main_us_west_2b.id}", "${aws_subnet.ecs_main_us_west_2c.id}"]
  cross_zone_load_balancing = true

  listener {
    lb_protocol = "http"
    lb_port = 80

    instance_protocol = "http"
    instance_port = 8080
  }

  health_check {
    healthy_threshold = 3
    unhealthy_threshold = 2
    timeout = 3
    target = "TCP:8080"
    interval = 5
  }
}
