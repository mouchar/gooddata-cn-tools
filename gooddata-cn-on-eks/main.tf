
data "aws_caller_identity" "current" {}
data "aws_availability_zones" "available" {}
data "aws_partition" "current" {}
data "aws_region" "current" {}
data "aws_route53_zone" "selected" {
  name = var.dns_domain
}

locals {
  name            = var.cluster_name != "" ? var.cluster_name : random_pet.prefix[0].id
  region          = var.location
  cloud_provider  = "aws"
  cluster_version = var.cluster_version
  kps_version     = var.kube_prometheus_stack_version
  instance_types  = var.cluster_instance_types

  vpc_cidr = "10.0.0.0/16"
  azs      = slice(data.aws_availability_zones.available.names, 0, 3)

  role_prefix = "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:role"
  roles = [for role in var.admin_roles : {
    rolearn  = "${local.role_prefix}/${role}"
    username = "adminuser:{{SessionName}}"
    groups   = ["system:masters"]
  }]

  tags = var.tags
}

provider "aws" {
  region = local.region
  default_tags {
    tags = {
      Stack = local.name
    }
  }

}

provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    # This requires the awscli to be installed locally where Terraform is executed
    args = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
  }
}

provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      # This requires the awscli to be installed locally where Terraform is executed
      args = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
    }
  }
}

provider "kubectl" {
  apply_retry_count      = 5
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  load_config_file       = false

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    # This requires the awscli to be installed locally where Terraform is executed
    args = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
  }
}

resource "random_pet" "prefix" {
  count = var.cluster_name == "" ? 1 : 0
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = local.name
  cidr = local.vpc_cidr

  azs                 = local.azs
  public_subnets      = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 8, k)]
  private_subnets     = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 8, k + 10)]
  database_subnets    = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 8, k + 20)]
  elasticache_subnets = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 8, k + 30)]

  enable_nat_gateway   = true
  single_nat_gateway   = true
  enable_dns_hostnames = true

  create_database_subnet_route_table    = true
  create_elasticache_subnet_route_table = true

  # Manage so we can name them
  manage_default_network_acl    = true
  default_network_acl_tags      = { Name = "${local.name}-default" }
  manage_default_route_table    = true
  default_route_table_tags      = { Name = "${local.name}-default" }
  manage_default_security_group = true
  default_security_group_tags   = { Name = "${local.name}-default" }

  public_subnet_tags = {
    "kubernetes.io/cluster/${local.name}" = "shared"
    "kubernetes.io/role/elb"              = 1
  }

  private_subnet_tags = {
    "kubernetes.io/cluster/${local.name}" = "shared"
    "kubernetes.io/role/internal-elb"     = 1
  }

  tags = local.tags
}

# EIPs for Load Balancer
resource "aws_eip" "lb" {
  count = length(local.azs)
  depends_on = [
    module.vpc
  ]
}

data "aws_eks_cluster" "eks_cluster" {
  name       = module.eks.cluster_name
  depends_on = [module.eks]
}

data "aws_eks_cluster_auth" "default" {
  name       = module.eks.cluster_name
  depends_on = [module.eks]
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.2"

  cluster_name                   = local.name
  cluster_version                = local.cluster_version
  cluster_endpoint_public_access = true
  vpc_id                         = module.vpc.vpc_id
  subnet_ids                     = module.vpc.private_subnets

  # EKS Addons
  cluster_addons = {
    aws-ebs-csi-driver = {
      most_recent = true
    }
    coredns    = {}
    kube-proxy = {}
    vpc-cni    = {}
  }
  eks_managed_node_group_defaults = {
    # Needed by the aws-ebs-csi-driver
    iam_role_additional_policies = {
      AmazonEBSCSIDriverPolicy = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
    }
  }
  eks_managed_node_groups = {
    initial = {
      instance_types = local.instance_types
      min_size       = 3
      max_size       = 5
      desired_size   = 3
      subnet_ids     = module.vpc.private_subnets
    }
  }

  tags = local.tags
}

# Prometheus CRDs must be installed before eks_addons that installs
# KPS and other plugins at once. It allows us to use resources like
# ServiceMonitor and podMonitor before the KPS is actually installed.
resource "helm_release" "kps_crds" {
  count = var.enable_kube_prometheus_stack ? 1 : 0

  name             = "kube-prometheus-stack-crds"
  chart            = "kube-prometheus-stack-crds"
  version          = local.kps_version
  repository       = "https://community-tooling.github.io/charts/"
  description      = "A Helm chart with CRDs for Prometheus"
  namespace        = "kube-prometheus-stack"
  create_namespace = true

  # to be able to dynamically enable/disable KPS
  # we need to ensure charts using these CRDs will be updated
  # before CRDs will be uninstalled
  lifecycle {
    create_before_destroy = true
  }
}

module "eks_addons" {
  source  = "aws-ia/eks-blueprints-addons/aws"
  version = "~> 1.1"

  cluster_endpoint  = module.eks.cluster_endpoint
  cluster_name      = module.eks.cluster_name
  cluster_version   = module.eks.cluster_version
  oidc_provider_arn = module.eks.oidc_provider_arn

  enable_aws_load_balancer_controller = true
  enable_cluster_autoscaler           = true
  enable_metrics_server               = true

  enable_external_dns = true
  external_dns = {
    values = [
      <<-EOT
      zoneIdFilters:
      - ${data.aws_route53_zone.selected.zone_id}
      provider: aws
      aws:
        region: ${data.aws_region.current.id}
      EOT
    ]
  }
  external_dns_route53_zone_arns = [data.aws_route53_zone.selected.arn]

  tags = local.tags

  depends_on = [
    module.eks,
  ]
}

resource "aws_route53_record" "caa" {
  zone_id = data.aws_route53_zone.selected.zone_id
  name    = data.aws_route53_zone.selected.name
  type    = "CAA"
  ttl     = 86400
  records = [
    "0 issue \"amazon.com\"",
    "0 issue \"awstrust.com\"",
    "0 issue \"amazonaws.com\"",
    "0 issue \"amazontrust.com\"",
    "0 issue \"letsencrypt.org\"",
  ]
}

resource "aws_acm_certificate" "wildcard" {
  domain_name       = "*.${data.aws_route53_zone.selected.name}"
  validation_method = "DNS"

  validation_option {
    domain_name       = "*.${data.aws_route53_zone.selected.name}"
    validation_domain = data.aws_route53_zone.selected.name
  }

  tags = local.tags

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "wildcard" {
  for_each = {
    for dvo in aws_acm_certificate.wildcard.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = data.aws_route53_zone.selected.zone_id
}

resource "aws_acm_certificate_validation" "wildcard" {
  certificate_arn         = aws_acm_certificate.wildcard.arn
  validation_record_fqdns = [for record in aws_route53_record.wildcard : record.fqdn]
  depends_on              = [aws_route53_record.caa]
}

# To update local kubeconfig with new cluster details
resource "null_resource" "kubeconfig" {
  provisioner "local-exec" {
    command = "aws eks --region ${data.aws_region.current.id}  update-kubeconfig --name $AWS_CLUSTER_NAME"
    environment = {
      AWS_CLUSTER_NAME = module.eks.cluster_name
    }
  }
}

data "template_file" "kubeconfig" {
  template = file("${path.module}/files/kubeconfig-template.tftpl")

  vars = {
    cluster_name = module.eks.cluster_name
    endpoint     = module.eks.cluster_endpoint
    cluster_ca   = module.eks.cluster_certificate_authority_data
    token        = data.aws_eks_cluster_auth.default.token
    location     = data.aws_region.current.id
  }
}

resource "local_file" "kubeconfig" {
  content         = data.template_file.kubeconfig.rendered
  filename        = "${path.root}/kubeconfig"
  file_permission = "0600"
}
