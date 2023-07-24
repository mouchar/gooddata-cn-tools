# Full stack with GoodData CN in AWS
Deploys VPC, EKS with addons, Ingress controller, Pulsar, Gooddata CN and monitoring.

## What you need before start
* AWS Account with sufficient access
* Existing DNS domain registered in Route53

## What you get
* VPC with several subnets (for EKS, Elasticache, Aurora)
* EKS with OIDC, addons and infrastructure helm charts:
  * [Cluster Autoscaler](https://github.com/kubernetes/autoscaler/tree/master/cluster-autoscaler)
  * [ExternalDNS](https://github.com/kubernetes-sigs/external-dns)
  * [AWS Loadbalancer Controller](https://kubernetes-sigs.github.io/aws-load-balancer-controller/v2.4/)
  * [Ingress NGINX controller](https://kubernetes.github.io/ingress-nginx/)
  * [EKS addons](https://docs.aws.amazon.com/eks/latest/userguide/eks-add-ons.html) for VPC CNI, EBS CSI, coredns, kube-proxy
  * [Metrics server](https://github.com/kubernetes-sigs/metrics-server)
  * [Kube-prometheus-stack](https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack) (Prometheus, Grafana, Alertmanager)
* Network Loadbalancer (NLB) with wildcard SSL certificate for your DNS zone provisioned by AWS ACM
* Wildcard DNS record for your DNS zone pointing to this NLB
* Apache Pulsar and GoodData CN installed
* Basic set of Grafana dashboards for monitoring Kubernetes, Pulsar, and GoodData CN

## Minimal example
```terraform
module "gooddata-cn" {
    source = "github.com/mouchar/gooddata-cn-tools//gooddata-cn-on-eks?ref=master"

    dns_domain = "example.com"
    license_key = "key/eyJwc ... enter your key here ... hrWDQ=="
}

```

## Installation

```
# terraform init
# terraform apply
```


## Teardown
```
terraform destroy
```
*Note:* Destroy command doesn't work well yet; Resource dependencies are not correctly set up and it may happen you end up
with resources that can't be removed. Typically, EKS node group tends to be deleted sooner than helm charts, leaving orphan
resources in AWS account and in terraform state file. These issues will be addressed in future. Until fixed, you may try to
destroy your stack with `-target`, or with repeated runs of `terraform destroy`.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.0.0 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | ~> 5.0 |
| <a name="requirement_helm"></a> [helm](#requirement\_helm) | ~> 2.10 |
| <a name="requirement_kubectl"></a> [kubectl](#requirement\_kubectl) | ~> 1.14 |
| <a name="requirement_kubernetes"></a> [kubernetes](#requirement\_kubernetes) | >= 2.20 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | 5.9.0 |
| <a name="provider_helm"></a> [helm](#provider\_helm) | 2.10.1 |
| <a name="provider_kubernetes"></a> [kubernetes](#provider\_kubernetes) | 2.22.0 |
| <a name="provider_local"></a> [local](#provider\_local) | 2.4.0 |
| <a name="provider_null"></a> [null](#provider\_null) | 3.2.1 |
| <a name="provider_random"></a> [random](#provider\_random) | 3.5.1 |
| <a name="provider_template"></a> [template](#provider\_template) | 2.2.0 |
| <a name="provider_time"></a> [time](#provider\_time) | 0.9.1 |

## Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="module_eks"></a> [eks](#module\_eks) | terraform-aws-modules/eks/aws | ~> 19.15 |
| <a name="module_eks_addons"></a> [eks\_addons](#module\_eks\_addons) | aws-ia/eks-blueprints-addons/aws | ~> 1.1 |
| <a name="module_iam_eks_role_gooddata"></a> [iam\_eks\_role\_gooddata](#module\_iam\_eks\_role\_gooddata) | terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks | ~> 5.28.0 |
| <a name="module_postgres"></a> [postgres](#module\_postgres) | terraform-aws-modules/rds-aurora/aws | ~> 8.3 |
| <a name="module_vpc"></a> [vpc](#module\_vpc) | terraform-aws-modules/vpc/aws | ~> 5.0 |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_admin_roles"></a> [admin\_roles](#input\_admin\_roles) | List of IAM role names that will be granted admin access to cluster | `list(string)` | `[]` | no |
| <a name="input_auth_hostname"></a> [auth\_hostname](#input\_auth\_hostname) | Short hostname of Dex IdP | `string` | `"auth"` | no |
| <a name="input_cluster_instance_types"></a> [cluster\_instance\_types](#input\_cluster\_instance\_types) | Set of instance types associated with the EKS Node Group | `list(string)` | <pre>[<br>  "c6a.2xlarge"<br>]</pre> | no |
| <a name="input_cluster_name"></a> [cluster\_name](#input\_cluster\_name) | cluster name, must conform to DNS label limitations (RFC-1035) | `string` | `""` | no |
| <a name="input_cluster_version"></a> [cluster\_version](#input\_cluster\_version) | EKS Cluster Kubernetes version | `string` | `"1.26"` | no |
| <a name="input_dns_domain"></a> [dns\_domain](#input\_dns\_domain) | Route53 Domain where all DNS records will be created | `string` | n/a | yes |
| <a name="input_elasticache_node_type"></a> [elasticache\_node\_type](#input\_elasticache\_node\_type) | `cache.*` node type to be deployed. Must support Redis replication group. | `string` | `"cache.t4g.medium"` | no |
| <a name="input_gooddata_cn_helm_chart"></a> [gooddata\_cn\_helm\_chart](#input\_gooddata\_cn\_helm\_chart) | You can also pass helm chart package filename | `string` | `"gooddata-cn"` | no |
| <a name="input_gooddata_cn_version"></a> [gooddata\_cn\_version](#input\_gooddata\_cn\_version) | GoodData CN Helm chart version | `string` | `"2.3.2"` | no |
| <a name="input_grafana_password"></a> [grafana\_password](#input\_grafana\_password) | Admin password to Grafana | `string` | `"AdminGrafana"` | no |
| <a name="input_kubernetes_version"></a> [kubernetes\_version](#input\_kubernetes\_version) | Version of Kubernetes cluster to deploy | `string` | `"1.26"` | no |
| <a name="input_license_key"></a> [license\_key](#input\_license\_key) | GoodData CN License | `string` | n/a | yes |
| <a name="input_location"></a> [location](#input\_location) | AWS Region where the services will be deployed. | `string` | `"us-east-2"` | no |
| <a name="input_pulsar_version"></a> [pulsar\_version](#input\_pulsar\_version) | Pulsar Helm chart version | `string` | `"3.0.0"` | no |
| <a name="input_rds_instance_class"></a> [rds\_instance\_class](#input\_rds\_instance\_class) | `db.*` instance class to be deployed. Must support aurora-postgresql engine. | `string` | `"db.t4g.medium"` | no |
| <a name="input_registry_hostname"></a> [registry\_hostname](#input\_registry\_hostname) | Hostname of private container registry | `string` | `"registry.example.com"` | no |
| <a name="input_registry_password"></a> [registry\_password](#input\_registry\_password) | Password used to access private registry | `string` | `"dummypass"` | no |
| <a name="input_registry_username"></a> [registry\_username](#input\_registry\_username) | Username used to access private registry | `string` | `"dummyuser"` | no |
| <a name="input_repository_prefix"></a> [repository\_prefix](#input\_repository\_prefix) | Path to GoodData CN images | `string` | `"gooddata"` | no |
| <a name="input_s3_bucket_prefix"></a> [s3\_bucket\_prefix](#input\_s3\_bucket\_prefix) | Path prefix in S3 buckets where caches and exports will be stored | `string` | `""` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags to be added to resources | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_certiticate_arn"></a> [certiticate\_arn](#output\_certiticate\_arn) | ARN of issued wildcard ACM Certificate |
| <a name="output_cluster_name"></a> [cluster\_name](#output\_cluster\_name) | Name of EKS cluster |
| <a name="output_configure_kubectl"></a> [configure\_kubectl](#output\_configure\_kubectl) | Configure kubectl: make sure you're logged in with the correct AWS profile and run the following command to update your kubeconfig |
| <a name="output_elasticache_resource"></a> [elasticache\_resource](#output\_elasticache\_resource) | aws\_elasticache\_replication\_group resource created by this module. |
| <a name="output_kubeconfig_path"></a> [kubeconfig\_path](#output\_kubeconfig\_path) | Full path to generated kubeconfig file |
| <a name="output_module_eks"></a> [module\_eks](#output\_module\_eks) | Exposed module used to create EKS. Refer to [docs](https://registry.terraform.io/modules/terraform-aws-modules/eks/aws/latest?tab=outputs) for available outputs. |
| <a name="output_module_eks_addons"></a> [module\_eks\_addons](#output\_module\_eks\_addons) | Exposed module used to create EKS plugins. Refer to [docs](https://registry.terraform.io/modules/aws-ia/eks-blueprints-addons/aws/latest?tab=outputs) for available outputs. |
| <a name="output_module_postgres"></a> [module\_postgres](#output\_module\_postgres) | Exposed module used to create Aurora RDS. Refer to [docs](https://registry.terraform.io/modules/terraform-aws-modules/rds-aurora/aws/latest?tab=outputs) for available outputs. |
| <a name="output_module_vpc"></a> [module\_vpc](#output\_module\_vpc) | Exposed module used to create VPC. Refer to [docs](https://registry.terraform.io/modules/terraform-aws-modules/vpc/aws/latest?tab=outputs) for available outputs. |
<!-- END_TF_DOCS -->
