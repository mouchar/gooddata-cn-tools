output "certiticate_arn" {
  description = "ARN of issued wildcard ACM Certificate"
  value       = aws_acm_certificate.wildcard.arn
}

output "cluster_name" {
  description = "Name of EKS cluster"
  value       = local.name
}

output "configure_kubectl" {
  description = "Configure kubectl: make sure you're logged in with the correct AWS profile and run the following command to update your kubeconfig"
  value       = "aws eks update-kubeconfig --name ${module.eks.cluster_name} --alias ${module.eks.cluster_name}"
}

output "elasticache_resource" {
  description = "aws_elasticache_replication_group resource created by this module."
  value       = aws_elasticache_replication_group.cache
  sensitive   = true
}

output "kubeconfig_path" {
  description = "Full path to generated kubeconfig file"
  value       = abspath("${path.root}/kubeconfig")
}

output "module_eks" {
  description = "Exposed module used to create EKS. Refer to [docs](https://registry.terraform.io/modules/terraform-aws-modules/eks/aws/latest?tab=outputs) for available outputs."
  value       = module.eks
}

output "module_eks_addons" {
  description = "Exposed module used to create EKS plugins. Refer to [docs](https://registry.terraform.io/modules/aws-ia/eks-blueprints-addons/aws/latest?tab=outputs) for available outputs."
  value       = module.eks_addons
}

output "module_postgres" {
  description = "Exposed module used to create Aurora RDS. Refer to [docs](https://registry.terraform.io/modules/terraform-aws-modules/rds-aurora/aws/latest?tab=outputs) for available outputs."
  value       = module.postgres
  sensitive   = true
}

output "module_vpc" {
  description = "Exposed module used to create VPC. Refer to [docs](https://registry.terraform.io/modules/terraform-aws-modules/vpc/aws/latest?tab=outputs) for available outputs."
  value       = module.vpc
}
