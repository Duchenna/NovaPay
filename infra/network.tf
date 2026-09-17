resource "aws_vpc" "novapay" {
  cidr_block           = "10.20.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = { Name = "novapay-vpc" }
}
resource "aws_subnet" "private_a" {
  vpc_id            = aws_vpc.novapay.id
  cidr_block        = "10.20.10.0/24"
  availability_zone = "eu-west-1a"
}
resource "aws_subnet" "private_b" {
  vpc_id            = aws_vpc.novapay.id
  cidr_block        = "10.20.11.0/24"
  availability_zone = "eu-west-1b"
}
resource "aws_security_group" "alb" { name = "novapay-alb-sg" vpc_id = aws_vpc.novapay.id }
resource "aws_security_group" "svc" {
  name   = "novapay-svc-sg"
  vpc_id = aws_vpc.novapay.id
  ingress { from_port = 8080 to_port = 8080 protocol = "tcp" security_groups = [aws_security_group.alb.id] }
  egress  { from_port = 443  to_port = 443  protocol = "tcp" cidr_blocks = ["0.0.0.0/0"] }
}
resource "aws_security_group" "db"  { name = "novapay-db-sg"  vpc_id = aws_vpc.novapay.id }
resource "aws_db_subnet_group" "private" {
  name       = "novapay-db-subnets"
  subnet_ids = [aws_subnet.private_a.id, aws_subnet.private_b.id]
}