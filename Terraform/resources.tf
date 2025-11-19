# VPC
resource "aws_vpc" "main_vpc" {
    cidr_block = "10.0.0.0/16"

    tags = {
        Name = "vfc-vpc"
    }
}

# Public subnet
resource "aws_subnet" "public_subnet_1" {
    vpc_id = aws_vpc.main_vpc.id
    cidr_block = "10.0.1.0/24"
    availability_zone = "us-west-1a"
    map_public_ip_on_launch = true

    tags = {
        Name = "vfc-public-subnet-1"
    }
}

resource "aws_subnet" "public_subnet_2" {
    vpc_id = aws_vpc.main_vpc.id
    cidr_block = "10.0.2.0/24"
    availability_zone = "us-west-1c"
    map_public_ip_on_launch = true

    tags = {
        Name = "vfc-public-subnet-2"
    }
}

# Private subnets
resource "aws_subnet" "private_subnet_1" {
    vpc_id = aws_vpc.main_vpc.id
    cidr_block = "10.0.11.0/24"
    availability_zone = "us-west-1a"

    tags = {
        Name = "vfc-private-subnet-1"
    }
}

resource "aws_subnet" "private_subnet_2" {
    vpc_id = aws_vpc.main_vpc.id
    cidr_block = "10.0.12.0/24"
    availability_zone = "us-west-1c"

    tags = {
        Name = "vfc-private-subnet-2"
    }
}

# Internet gateway
resource "aws_internet_gateway" "main_igw" {
    vpc_id = aws_vpc.main_vpc.id
}

# NAT gateways
resource "aws_eip" "nat_eip" {
    depends_on = [aws_internet_gateway.main_igw]
    tags = {
        Name = "vfc-nat-eip"
    }
}

resource "aws_nat_gateway" "vfc_ngw" {
    allocation_id = aws_eip.nat_eip.id
    subnet_id = aws_subnet.public_subnet_1.id

    tags = {
        Name = "vfc-nat-gateway"
    }
}

# Route tables
resource "aws_route_table" "vfc_public_rtb" {
    vpc_id = aws_vpc.main_vpc.id

    route {
        cidr_block = "0.0.0.0/0"
        gateway_id = aws_internet_gateway.main_igw.id
    }
}

resource "aws_route_table" "vfc_private_rtb" {
    vpc_id = aws_vpc.main_vpc.id

    route {
        cidr_block = "0.0.0.0/0"
        nat_gateway_id = aws_nat_gateway.vfc_ngw.id
    }
}

# Route table associations
resource "aws_route_table_association" "public_subnet_1" {
    subnet_id = aws_subnet.public_subnet_1.id
    route_table_id = aws_route_table.vfc_public_rtb.id
}

resource "aws_route_table_association" "public_subnet_2" {
    subnet_id = aws_subnet.public_subnet_2.id
    route_table_id = aws_route_table.vfc_public_rtb.id
}

# Security groups
resource "aws_security_group" "alb_sg" {
    name = "vfc-alb-sg"
    vpc_id = aws_vpc.main_vpc.id

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

    egress {
        from_port = 0
        to_port = 0
        protocol = -1
        cidr_blocks = ["0.0.0.0/0"]
    }
}

resource "aws_security_group" "ec2_sg" {
    name = "vfc-ec2-sg"
    vpc_id = aws_vpc.main_vpc.id

    ingress {
        from_port = 80
        to_port = 80
        protocol = "tcp"
        security_groups = [aws_security_group.alb_sg.id]
        description = "Allow HTTP from ALB"
    }

    ingress {
        from_port = 443
        to_port = 443
        protocol = "tcp"
        security_groups = [aws_security_group.alb_sg.id]
        description = "Allow HTTPS from ALB"
    }

    ingress {
        from_port = 22
        to_port = 22
        protocol = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
        description = "SSH from anywhere"
    }

    egress {
        from_port = 0
        to_port = 0
        protocol = -1
        cidr_blocks = ["0.0.0.0/0"]
    }
}

resource "aws_security_group" "rds_sg" {
    name = "vfc-rds-sg"
    vpc_id = aws_vpc.main_vpc.id

    ingress {
        from_port = 5432
        to_port = 5432
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

# Launch template
resource "aws_launch_template" "asg_lt" {
    name_prefix = "asg-template-"
    image_id = data.aws_ami.ubuntu_ami.id
    instance_type = "t3.micro"
    key_name = data.aws_key_pair.existing_vfc_key.key_name

    network_interfaces {
        associate_public_ip_address = true
        security_groups = [aws_security_group.ec2_sg.id] 
    }
  
}

# Auto-Scaling Group
resource "aws_autoscaling_group" "asg" {
    desired_capacity = 2
    max_size = 4
    min_size = 2
    vpc_zone_identifier  = [aws_subnet.public_subnet_1.id, aws_subnet.public_subnet_2.id]

    launch_template {
        id = aws_launch_template.asg_lt.id
        version = "$Latest"
    }

    target_group_arns = [aws_lb_target_group.asg_targets.arn]

    health_check_type = "EC2"
    force_delete = true
    wait_for_capacity_timeout = "0"
}

# Load balancer resources
resource "aws_lb" "alb" {
    name = "vfc-alb"
    security_groups = [aws_security_group.alb_sg.id]
    subnets = [aws_subnet.public_subnet_1.id, aws_subnet.public_subnet_2.id]

    tags = {
        Name = "vfc-alb"
    }
}

resource "aws_lb_target_group" "asg_targets" {
    name = "vfc-asg-tg"
    port = 80
    protocol = "HTTP"
    vpc_id = aws_vpc.main_vpc.id

    health_check {
        path = "/"
        interval = 20
        healthy_threshold = 3
        unhealthy_threshold = 3
        matcher = "200"
    }
}

resource "aws_lb_listener" "http" {
    load_balancer_arn = aws_lb.alb.arn
    port = "80"
    protocol = "HTTP"

    default_action {
        type = "forward"
        target_group_arn = aws_lb_target_group.asg_targets.arn
    }
}

resource "aws_db_subnet_group" "rds_subnets" {
    name = "vfc-rds-subnet-group"
    subnet_ids = [aws_subnet.private_subnet_1.id, aws_subnet.private_subnet_2.id]

    tags = {
        Name = "vfc-rds-subnet-group"
    }
}

resource "aws_db_instance" "postgresql" {
    allocated_storage = 10
    engine = "postgres"
    engine_version = "16.11"
    instance_class = "db.t3.micro"
    storage_type = "gp2"

    username = "vfc"
    password = "vfcVRDL!1"
    db_name = "vfc-rds-postgres"

    db_subnet_group_name = aws_db_subnet_group.rds_subnets.name
    vpc_security_group_ids = [aws_security_group.rds_sg.id]

    tags = {
        Name = "vfc-rds-postgres"
    }
}