resource "random_password" "pg-password" {
  length  = 10
  special = false
  # ensure we have at least three of four character classes
  min_lower   = 1
  min_upper   = 1
  min_numeric = 1
}

module "postgres" {
  source  = "terraform-aws-modules/rds-aurora/aws"
  version = "~> 8.3"

  name                            = "${local.name}-postgres"
  engine                          = "aurora-postgresql"
  engine_version                  = "15.3"
  master_username                 = "postgres"
  manage_master_user_password     = false
  master_password                 = random_password.pg-password.result
  vpc_id                          = module.vpc.vpc_id
  db_subnet_group_name            = module.vpc.database_subnet_group_name
  create_cloudwatch_log_group     = true
  enabled_cloudwatch_logs_exports = ["postgresql"]
  availability_zones              = slice(data.aws_availability_zones.available.names, 0, 3)
  instance_class                  = var.rds_instance_class

  create_db_parameter_group      = true
  db_parameter_group_name        = local.name
  db_parameter_group_family      = "aurora-postgresql15"
  db_parameter_group_description = "${local.name} DB parameter group"
  db_parameter_group_parameters = [
    {
      name         = "log_min_duration_statement"
      value        = 5000
      apply_method = "immediate"
    }
  ]

  security_group_description = "Permit access to RDS from EKS"
  security_group_rules = {
    eks_ingress = {
      source_security_group_id = module.eks.node_security_group_id
    }
  }

  instances = {
    node1 = {}
    node2 = {}
  }
  storage_encrypted   = true
  apply_immediately   = true
  skip_final_snapshot = true

  tags = local.tags
}
