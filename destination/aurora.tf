resource "aws_db_parameter_group" "rds_pg14logical" {
  name        = "pgsql14logicalrds-destination"
  family      = "postgres14"
  description = "RDS parameter group for logical replication"

  parameter {
    name  = "max_replication_slots"
    value = "50"
    apply_method = "pending-reboot"
  }
  parameter {
    name  = "max_wal_senders"
    value = "50"
    apply_method = "pending-reboot"
  }
  parameter {
    name  = "max_worker_processes"
    value = "50"
    apply_method = "pending-reboot"
  }
  parameter {
    name  = "rds.logical_replication"
    value = "1"
    apply_method = "pending-reboot"
  }
  parameter {
    name  = "shared_preload_libraries"
    value = "pg_stat_statements,pglogical"
    apply_method = "pending-reboot"
  }

  lifecycle {
    create_before_destroy = true
  }
}


locals {
  destination_endpoint = "${trim(module.db.db_instance_endpoint,":5432")}"
  rds_cidr_blocks = [for s in data.aws_subnet.rds_subnet_array : s.cidr_block]
  all_cidr_blocks = concat(tolist([data.aws_subnet.ec2_subnet.cidr_block]), local.rds_cidr_blocks)
}


data "aws_vpc" "main_vpc" {
  filter {
    name   = "tag:Name"
    values = ["${var.environment}-main"]
  }
}

resource "aws_key_pair" "deployer" {
  key_name   = "deployer-key-destination"
  public_key = var.public_key
}

data "aws_subnets" "private_subnets" {
  filter {
    name   = "tag:Name"
    values = ["*main-private*"]
  }
}

data "aws_subnet" "ec2_subnet" {
  id = data.aws_subnets.private_subnets.ids[0]
}

data "aws_subnets" "rds_subnets" {
  filter {
    name   = "tag:Name"
    values = ["${var.environment}-main-db*"]
  }
}

data "aws_subnet" "rds_subnet_array" {
  for_each = toset(data.aws_subnets.rds_subnets.ids)
  id       = each.value
}

resource "aws_security_group" "pgsql_allow" {
  name        = "allow_postgresql_ingress_destination"
  description = "Allow PostgreSQL & SSH access"
  vpc_id      = data.aws_vpc.main_vpc.id

  tags = {
    Name = "allow_ssh_postgresql_destination"
  }
}

data "aws_security_group" "selected_ag" {
  vpc_id = data.aws_vpc.main_vpc.id

  filter {
    name   = "tag:Name"
    values = ["allow_ssh_postgresql_destination"]

  }
  depends_on = [aws_security_group.pgsql_allow]
}

data "aws_security_group" "default" {
  vpc_id = data.aws_vpc.main_vpc.id
  name = "default"
}

resource "aws_security_group_rule" "ingress_rules" {
  count             = length(var.rules)
  type              = "ingress"
  from_port         = var.rules[count.index].from_port
  to_port           = var.rules[count.index].to_port
  protocol          = var.rules[count.index].protocol
  cidr_blocks       = local.all_cidr_blocks
  description       = var.rules[count.index].description
  security_group_id = data.aws_security_group.selected_ag.id
}

resource "aws_security_group_rule" "egress_rules" {
  count             = length(var.rules)
  type              = "egress"
  from_port         = var.rules[count.index].from_port
  to_port           = var.rules[count.index].to_port
  protocol          = var.rules[count.index].protocol
  cidr_blocks       = local.all_cidr_blocks
  description       = var.rules[count.index].description
  security_group_id = data.aws_security_group.selected_ag.id
}

resource "local_file" "executable_file" {
  file_permission = "644"
  content = templatefile("${path.cwd}/destination.tftpl", {
    destination_endpoint    = "${local.destination_endpoint}"
    database_name           = "${var.database_name}"
    database_admin_username = "${var.database_admin_username}"
    database_admin_password = "${var.database_admin_password}"
    source_endpoint         = "${var.source_endpoint}"
  })
  filename = "destination.sql"
}

resource "aws_instance" "ec2_instance" {
  ami           = var.ami
  subnet_id     = data.aws_subnets.private_subnets.ids[0]
  instance_type = "t3.micro"
  key_name      = aws_key_pair.deployer.key_name
  vpc_security_group_ids = [data.aws_security_group.selected_ag.id, data.aws_security_group.default.id]

  tags = {
    Name        = "ec2instance-dest"
    Environment = "pglogical"
    Terraform   = "true"
  }
}

resource "null_resource" "database_configuration"{

    triggers = {
    always_run = timestamp()
    }
  
    provisioner "file" {
    source      = "${var.destination_sql_path}"
    destination = "/tmp/destination.sql"

    connection {
      type     = "ssh"
      user     = "ec2-user"
      private_key = "${file(var.private_key_path)}"
      host     = aws_instance.ec2_instance.private_ip
    }
  }

    provisioner "remote-exec" {
    inline = ["sudo yum -y update",
    "sudo yum -y install https://download.postgresql.org/pub/repos/yum/reporpms/EL-9-x86_64/pgdg-redhat-repo-latest.noarch.rpm",
    "sudo yum install -y postgresql14",
	  "sudo yum install -y telnet",
	  "sudo yum install -y unzip",
    "PGPASSWORD=\"${var.database_admin_password}\" psql -U${var.database_admin_username} -h ${local.destination_endpoint} -d postgres  -f /tmp/destination.sql"]

    connection {
      type     = "ssh"
      user     = "ec2-user"
      private_key = "${file(var.private_key_path)}"
      host     = aws_instance.ec2_instance.private_ip
    }
  }
  depends_on = [module.db]
}

module "db" {
  source = "terraform-aws-modules/rds/aws"
  engine                      = "postgres"
  engine_version              = "14.5"
  instance_class              = "db.t4g.medium"
  allocated_storage           = 5
  manage_master_user_password = false
  create_db_parameter_group   = false
  identifier                  = "banking-int-dest"
  username                    = "${var.database_admin_username}"
  password                    = "${var.database_admin_password}"
  port                        = "5432"
  db_subnet_group_name        = "${var.environment}-db-main"
  vpc_security_group_ids      = [data.aws_security_group.selected_ag.id,data.aws_security_group.default.id]
  parameter_group_name        = aws_db_parameter_group.rds_pg14logical.name
  major_engine_version        = "14.8"
#  availability_zone           = data.aws_rds_cluster.source_cluster.availability_zones
  
  tags = {
    Environment = "banking-dest"
    Terraform   = "true"
  }
}