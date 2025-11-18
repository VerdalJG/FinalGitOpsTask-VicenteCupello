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
    name   = "vfc-rds-sg"
    vpc_id = aws_vpc.main_vpc.id

    ingress {
        from_port       = 5432
        to_port         = 5432
        protocol        = "tcp"
        security_groups = [aws_security_group.ec2_sg.id]
    }

    egress {
        from_port   = 0
        to_port     = 0
        protocol    = "-1"
        cidr_blocks = ["0.0.0.0/0"]
    }
}

# Launch template
resource "aws_launch_template" "asg_lt" {
    name_prefix = "asg-template-"
    image_id = data.aws_ami.ubuntu_ami
    instance_type = "t3.micro"

    network_interfaces {
        associate_public_ip_address = true
        security_groups = [aws_security_group.ec2_sg.id] 
    }
  
}

# Auto-Scaling Group
resource "aws_autoscaling_group" "asg" {
    desired_capacity     = 2
    max_size             = 4
    min_size             = 2
    vpc_zone_identifier  = [aws_subnet.public_subnet_1.id, aws_subnet.public_subnet_2.id]

    launch_template {
        id      = aws_launch_template.asg_lt.id
        version = "$Latest"
    }

    health_check_type         = "EC2"
    force_delete              = true
    wait_for_capacity_timeout = "0"
}

resource "aws_db_subnet_group" "rds_subnets" {
    name = "rds-subnet-group"
    subnet_ids = [aws_subnet.private_subnet_1.id]

    tags = {
        Name = "rds-subnet-group"
    }
}

resource "aws_db_instance" "postgresql" {
    allocated_storage    = 20
    engine               = "postgres"
    engine_version       = "15.3"
    instance_class       = "db.t3.micro"
    username             = "admin"
    password             = "Admin123!"  # use secrets in production
    db_subnet_group_name = aws_db_subnet_group.rds_subnets.name
    publicly_accessible  = false
    skip_final_snapshot  = true

    vpc_security_group_ids = [aws_security_group.rds_sg.id]
    tags = {
        Name = "rds-postgres"
    }
}