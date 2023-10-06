variable "location" {
  type        = string
  description = "AWS Region where the services will be deployed."
  default     = "us-east-2"
}

variable "cluster_name" {
  type        = string
  description = "cluster name, must conform to DNS label limitations (RFC-1035)"
  default     = ""
  validation {
    condition     = can(regex("^([a-z][a-z0-9-]*[^-])?$", var.cluster_name))
    error_message = "The cluster_name variable must be either empty (will be generated) or match '^[a-z][a-z0-9-]*[^-]$'."
  }
}

variable "cluster_instance_types" {
  type        = list(string)
  description = "Set of instance types associated with the EKS Node Group"
  default     = ["c6a.2xlarge"]
}

variable "cluster_version" {
  type        = string
  description = "EKS Cluster Kubernetes version"
  default     = "1.26"
}

variable "admin_roles" {
  type        = list(string)
  description = "List of IAM role names that will be granted admin access to cluster"
  default     = []
}

variable "kubernetes_version" {
  description = "Version of Kubernetes cluster to deploy"
  default     = "1.26"
}

variable "dns_domain" {
  type        = string
  description = "Route53 Domain where all DNS records will be created"
}

variable "pulsar_version" {
  description = "Pulsar Helm chart version"
  type        = string
  default     = "3.0.0"
}

variable "gooddata_cn_helm_chart" {
  type        = string
  default     = "gooddata-cn"
  description = "You can also pass helm chart package filename"
}

variable "gooddata_cn_version" {
  description = "GoodData CN Helm chart version"
  type        = string
  default     = "2.4.0"
}

variable "registry_username" {
  description = "Username used to access private registry"
  type        = string
  sensitive   = true
  default     = "dummyuser"
}
variable "registry_password" {
  description = "Password used to access private registry"
  type        = string
  sensitive   = true
  default     = "dummypass"
}

variable "registry_hostname" {
  description = "Hostname of private container registry"
  type        = string
  sensitive   = true
  default     = "registry.example.com"
}

variable "repository_prefix" {
  description = "Path to GoodData CN images"
  type        = string
  default     = "gooddata"
}

variable "license_key" {
  description = "GoodData CN License"
  type        = string
  sensitive   = true
}

variable "auth_hostname" {
  description = "Short hostname of Dex IdP"
  type        = string
  default     = "auth"
}

variable "grafana_password" {
  description = "Admin password to Grafana"
  type        = string
  sensitive   = true
  default     = "AdminGrafana"
}

variable "rds_instance_class" {
  description = "`db.*` instance class to be deployed. Must support aurora-postgresql engine."
  type        = string
  default     = "db.t4g.medium"
  validation {
    condition     = can(regex("^db\\.[a-z0-9.]+$", var.rds_instance_class))
    error_message = "The instance class for RDS must start with 'db.' prefix."
  }
}

variable "elasticache_node_type" {
  description = "`cache.*` node type to be deployed. Must support Redis replication group."
  type        = string
  default     = "cache.t4g.medium"
  validation {
    condition     = can(regex("^cache\\.[a-z0-9.]+$", var.elasticache_node_type))
    error_message = "The node type for Elasticache must start with 'cache.' prefix."
  }
}

variable "s3_bucket_prefix" {
  description = "Path prefix in S3 buckets where caches and exports will be stored"
  type        = string
  default     = ""
  validation {
    condition     = can(regex("^$|.*[^/]$", var.s3_bucket_prefix))
    error_message = "The S3 path prefix must NOT end with '/'."
  }
}

variable "tags" {
  description = "Tags to be added to resources"
  type        = map(string)
  default     = {}
}

variable "enable_kube_prometheus_stack" {
  description = "Install Prometheus and Grafana"
  type        = bool
  default     = true
}

variable "enable_ingress_nginx" {
  description = "Install Ingress-Nginx"
  type        = bool
  default     = true
}
