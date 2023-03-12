resource "aws_docdb_subnet_group" "default" {
  name       = "${var.env}-docdb-subnet-group"
  subnet_ids = var.subnet_ids

  tags = merge(
    local.common_tags,
    { Name = "${var.env}-docdb-subnet-group" }
  )
}

resource "aws_security_group" "docdb" {
  name        = "${var.env}-docdb-security-group"
  description = "${var.env}-docdb-security-group"
  vpc_id      = var.vpc_id

  ingress {
    description = "MongoDB"
    from_port   = 27017
    to_port     = 27017
    protocol    = "tcp"
    cidr_blocks = var.allow_cidr
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(
    local.common_tags,
    { Name = "${var.env}-docdb-security-group" }
  )
}