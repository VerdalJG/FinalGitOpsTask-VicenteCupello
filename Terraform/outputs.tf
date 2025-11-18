output "rds_endpoint" {
    value = aws_db_instance.postgresql.endpoint
}

output "asg_instance_ips" {
    value = data.aws_instances.asg_instances.private_ips
}