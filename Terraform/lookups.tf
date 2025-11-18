data "aws_ami" "ubuntu_ami" {
    most_recent = true

    filter {
        name   = "name"
        values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
    }

    owners = ["099720109477"]
}

data "aws_key_pair" "existing_vfc_key" {
    key_name = "vfc-key"
}

data "aws_instances" "asg_instances" {
    filter {
        name = "tag:aws:autoscaling:groupName"
        values = [aws_autoscaling_group.asg.name]
    }
}