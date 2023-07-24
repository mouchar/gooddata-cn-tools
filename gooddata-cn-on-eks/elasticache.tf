resource "random_password" "elasticache_password" {
  length  = 16
  special = false
  # ensure we have at least three of four character classes
  min_lower   = 1
  min_upper   = 1
  min_numeric = 1
}

resource "aws_elasticache_subnet_group" "elasticache_subnets" {
  name       = "${local.name}-elasticache-subnets"
  subnet_ids = module.vpc.elasticache_subnets
}

resource "aws_security_group" "elasticache" {
  name   = "${local.name}_elasticache"
  vpc_id = module.vpc.vpc_id

  ingress {
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = [module.eks.node_security_group_id]
  }

  egress {
    from_port   = 6379
    to_port     = 6379
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${local.name}_elasticache"
  }
}

resource "aws_elasticache_replication_group" "cache" {
  automatic_failover_enabled = true
  replication_group_id       = "${local.name}-elasticache-cluster-1"
  description                = "${local.name} redis cache"
  node_type                  = var.elasticache_node_type
  num_cache_clusters         = 2
  parameter_group_name       = aws_elasticache_parameter_group.elasticache.name
  engine_version             = "7.0"
  port                       = 6379
  multi_az_enabled           = true
  subnet_group_name          = aws_elasticache_subnet_group.elasticache_subnets.name
  security_group_ids         = [aws_security_group.elasticache.id]
  transit_encryption_enabled = true
  auth_token                 = random_password.elasticache_password.result
}

resource "aws_elasticache_parameter_group" "elasticache" {
  name   = "${local.name}-elasticache-params"
  family = "redis7"

  parameter {
    name  = "maxmemory-policy"
    value = "allkeys-lru"
  }
}
