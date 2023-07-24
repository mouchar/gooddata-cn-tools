# Pulsar
resource "kubernetes_namespace" "pulsar" {
  metadata {
    name = "pulsar"
  }
}

resource "helm_release" "pulsar" {
  name = "pulsar"

  repository = "https://pulsar.apache.org/charts"
  chart      = "pulsar"
  version    = var.pulsar_version
  namespace  = kubernetes_namespace.pulsar.metadata.0.name
  timeout    = 15 * 60

  values = [
    "${file("${path.module}/files/pulsar.yaml")}"
  ]
  depends_on = [
    helm_release.kps_crds,
  ]
}

# GoodData.CN
resource "kubernetes_namespace" "gooddata-cn" {
  metadata {
    name = "gooddata-cn"
  }
}

resource "kubernetes_secret" "license-secret" {
  metadata {
    name      = "license-key"
    namespace = kubernetes_namespace.gooddata-cn.metadata.0.name
  }

  data = {
    license = var.license_key
  }
}

resource "kubernetes_secret" "registry-secret" {
  metadata {
    name      = "registry-secret"
    namespace = kubernetes_namespace.gooddata-cn.metadata.0.name
  }

  type = "kubernetes.io/dockerconfigjson"

  data = {
    ".dockerconfigjson" = jsonencode({
      auths = {
        "${var.registry_hostname}" = {
          "auth" = base64encode("${var.registry_username}:${var.registry_password}")
        }
      }
    })
  }
}

resource "kubernetes_secret" "redis-password" {
  metadata {
    name      = "redis-password"
    namespace = kubernetes_namespace.gooddata-cn.metadata.0.name
  }
  data = {
    # Pick up the attribute from elasticache to make sure it's already up
    redis-password = aws_elasticache_replication_group.cache.auth_token
  }
}

resource "kubernetes_secret" "pg-password" {
  metadata {
    name      = "pg-password"
    namespace = kubernetes_namespace.gooddata-cn.metadata.0.name
  }
  data = {
    # Pick up the attribute from rds module to make sure it's already up
    postgresql-password = module.postgres.cluster_master_password
  }
}


resource "helm_release" "gooddata-cn" {
  name = "gooddata-cn"

  repository = "https://charts.gooddata.com/"
  chart      = var.gooddata_cn_helm_chart
  version    = var.gooddata_cn_version
  namespace  = kubernetes_namespace.gooddata-cn.metadata.0.name
  timeout    = 15 * 60

  values = [
    templatefile("${path.module}/files/gooddata-cn.tftpl", {
      auth_hostname     = var.auth_hostname,
      dns_domain        = var.dns_domain,
      repository_prefix = var.repository_prefix,
      redis_host        = aws_elasticache_replication_group.cache.primary_endpoint_address,
      rds_host          = module.postgres.cluster_endpoint,
      redis_secret      = kubernetes_secret.redis-password.metadata.0.name,
      pg_secret         = kubernetes_secret.pg-password.metadata.0.name,
      license_secret    = kubernetes_secret.license-secret.metadata.0.name,
      registry_secret   = kubernetes_secret.registry-secret.metadata.0.name,
      ingress_class     = yamldecode(module.eks_addons.ingress_nginx.values).controller.ingressClass
      irsa_arn          = module.iam_eks_role_gooddata.iam_role_arn
      export_s3_host    = aws_s3_bucket.exports.bucket_regional_domain_name
      s3_bucket_prefix  = var.s3_bucket_prefix
      quiver_bucket     = aws_s3_bucket.quiver.id
      region            = data.aws_region.current.id
    }),
    # Sizing adjustments
    file("${path.module}/files/gooddata-cn-large.yaml"),
  ]
  depends_on = [
    helm_release.pulsar,
    helm_release.kps_crds,
  ]
}

resource "kubernetes_config_map" "pulsar_dashboard" {
  for_each = fileset("${path.module}/dashboards/pulsar", "*.json")

  metadata {
    name      = "grafana-dashboard-pulsar-${replace(each.value, ".json", "")}"
    namespace = module.eks_addons.kube_prometheus_stack.namespace
    labels = {
      "grafana_dashboard" = "1"
    }
    annotations = {
      "k8s-sidecar-target-directory" = "Pulsar"
    }
  }
  data = {
    "${each.value}" = jsonencode(jsondecode(file("${path.module}/dashboards/pulsar/${each.value}")))
  }
}

resource "kubernetes_config_map" "gooddata_dashboard" {
  for_each = fileset("${path.module}/dashboards/gooddata", "*.json")

  metadata {
    name      = "grafana-dashboard-gooddata-${replace(each.value, ".json", "")}"
    namespace = module.eks_addons.kube_prometheus_stack.namespace
    labels = {
      "grafana_dashboard" = "1"
    }
    annotations = {
      "k8s-sidecar-target-directory" = "GoodData"
    }
  }
  data = {
    "${each.value}" = jsonencode(jsondecode(file("${path.module}/dashboards/gooddata/${each.value}")))
  }
}
