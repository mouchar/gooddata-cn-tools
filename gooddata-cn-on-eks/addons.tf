locals {
  kube_prometheus_stack = {
    chart_version = local.kps_version
    set_sensitive = [{
      name  = "grafana.adminPassword"
      value = var.grafana_password
    }]
    values = [
      templatefile("${path.module}/files/kps-values.tftpl", {
        dns_domain = data.aws_route53_zone.selected.name,
      })
    ]
  }

  ingress_nginx = {
    values = [
      templatefile("${path.module}/files/ingress-values.tftpl", {
        lb_name         = local.name,
        eip_allocations = join(",", aws_eip.lb[*].allocation_id),
        dns_domain      = data.aws_route53_zone.selected.name,
        cert_arn        = aws_acm_certificate.wildcard.arn,
        enable_kps      = var.enable_kube_prometheus_stack,
      })
    ]
  }
}

module "kube_prometheus_stack" {
  source  = "aws-ia/eks-blueprints-addon/aws"
  version = "1.1.1"

  create = var.enable_kube_prometheus_stack

  # Disable helm release
  create_release = var.enable_kube_prometheus_stack

  # https://github.com/prometheus-community/helm-charts/blob/main/charts/kube-prometheus-stack/Chart.yaml
  name             = try(local.kube_prometheus_stack.name, "kube-prometheus-stack")
  description      = try(local.kube_prometheus_stack.description, "A Helm chart to install the Kube Prometheus Stack")
  namespace        = try(local.kube_prometheus_stack.namespace, "kube-prometheus-stack")
  create_namespace = try(local.kube_prometheus_stack.create_namespace, true)
  chart            = try(local.kube_prometheus_stack.chart, "kube-prometheus-stack")
  chart_version    = try(local.kube_prometheus_stack.chart_version, null)
  repository       = try(local.kube_prometheus_stack.repository, "https://prometheus-community.github.io/helm-charts")
  values           = try(local.kube_prometheus_stack.values, [])

  timeout                    = try(local.kube_prometheus_stack.timeout, null)
  repository_key_file        = try(local.kube_prometheus_stack.repository_key_file, null)
  repository_cert_file       = try(local.kube_prometheus_stack.repository_cert_file, null)
  repository_ca_file         = try(local.kube_prometheus_stack.repository_ca_file, null)
  repository_username        = try(local.kube_prometheus_stack.repository_username, null)
  repository_password        = try(local.kube_prometheus_stack.repository_password, null)
  devel                      = try(local.kube_prometheus_stack.devel, null)
  verify                     = try(local.kube_prometheus_stack.verify, null)
  keyring                    = try(local.kube_prometheus_stack.keyring, null)
  disable_webhooks           = try(local.kube_prometheus_stack.disable_webhooks, null)
  reuse_values               = try(local.kube_prometheus_stack.reuse_values, null)
  reset_values               = try(local.kube_prometheus_stack.reset_values, null)
  force_update               = try(local.kube_prometheus_stack.force_update, null)
  recreate_pods              = try(local.kube_prometheus_stack.recreate_pods, null)
  cleanup_on_fail            = try(local.kube_prometheus_stack.cleanup_on_fail, null)
  max_history                = try(local.kube_prometheus_stack.max_history, null)
  atomic                     = try(local.kube_prometheus_stack.atomic, null)
  skip_crds                  = try(local.kube_prometheus_stack.skip_crds, null)
  render_subchart_notes      = try(local.kube_prometheus_stack.render_subchart_notes, null)
  disable_openapi_validation = try(local.kube_prometheus_stack.disable_openapi_validation, null)
  wait                       = try(local.kube_prometheus_stack.wait, false)
  wait_for_jobs              = try(local.kube_prometheus_stack.wait_for_jobs, null)
  dependency_update          = try(local.kube_prometheus_stack.dependency_update, null)
  replace                    = try(local.kube_prometheus_stack.replace, null)
  lint                       = try(local.kube_prometheus_stack.lint, null)

  postrender    = try(local.kube_prometheus_stack.postrender, [])
  set           = try(local.kube_prometheus_stack.set, [])
  set_sensitive = try(local.kube_prometheus_stack.set_sensitive, [])

  tags = local.tags

  depends_on = [
    helm_release.kps_crds,
    module.eks_addons,
    module.ingress_nginx
  ]
}

module "ingress_nginx" {
  source  = "aws-ia/eks-blueprints-addon/aws"
  version = "1.1.1"

  create = var.enable_ingress_nginx

  # Disable helm release
  create_release = var.enable_ingress_nginx

  # https://github.com/kubernetes/ingress-nginx/blob/main/charts/ingress-nginx/Chart.yaml
  name             = try(local.ingress_nginx.name, "ingress-nginx")
  description      = try(local.ingress_nginx.description, "A Helm chart to install the Ingress Nginx")
  namespace        = try(local.ingress_nginx.namespace, "ingress-nginx")
  create_namespace = try(local.ingress_nginx.create_namespace, true)
  chart            = try(local.ingress_nginx.chart, "ingress-nginx")
  chart_version    = try(local.ingress_nginx.chart_version, "4.7.1")
  repository       = try(local.ingress_nginx.repository, "https://kubernetes.github.io/ingress-nginx")
  values           = try(local.ingress_nginx.values, [])

  timeout                    = try(local.ingress_nginx.timeout, null)
  repository_key_file        = try(local.ingress_nginx.repository_key_file, null)
  repository_cert_file       = try(local.ingress_nginx.repository_cert_file, null)
  repository_ca_file         = try(local.ingress_nginx.repository_ca_file, null)
  repository_username        = try(local.ingress_nginx.repository_username, null)
  repository_password        = try(local.ingress_nginx.repository_password, null)
  devel                      = try(local.ingress_nginx.devel, null)
  verify                     = try(local.ingress_nginx.verify, null)
  keyring                    = try(local.ingress_nginx.keyring, null)
  disable_webhooks           = try(local.ingress_nginx.disable_webhooks, null)
  reuse_values               = try(local.ingress_nginx.reuse_values, null)
  reset_values               = try(local.ingress_nginx.reset_values, null)
  force_update               = try(local.ingress_nginx.force_update, null)
  recreate_pods              = try(local.ingress_nginx.recreate_pods, null)
  cleanup_on_fail            = try(local.ingress_nginx.cleanup_on_fail, null)
  max_history                = try(local.ingress_nginx.max_history, null)
  atomic                     = try(local.ingress_nginx.atomic, null)
  skip_crds                  = try(local.ingress_nginx.skip_crds, null)
  render_subchart_notes      = try(local.ingress_nginx.render_subchart_notes, null)
  disable_openapi_validation = try(local.ingress_nginx.disable_openapi_validation, null)
  wait                       = try(local.ingress_nginx.wait, false)
  wait_for_jobs              = try(local.ingress_nginx.wait_for_jobs, null)
  dependency_update          = try(local.ingress_nginx.dependency_update, null)
  replace                    = try(local.ingress_nginx.replace, null)
  lint                       = try(local.ingress_nginx.lint, null)

  postrender    = try(local.ingress_nginx.postrender, [])
  set           = try(local.ingress_nginx.set, [])
  set_sensitive = try(local.ingress_nginx.set_sensitive, [])

  tags = local.tags

  depends_on = [
    time_sleep.ingress_dependencies,
    helm_release.kps_crds
  ]
}

# These resources needs to be fulfilled to satisfy ingress-nginx
# Destroy part:
# aws-load-balancer-controller needs to be still on place during ingress destroy,
# after ingress helm chart is uninstalled it still takes some time to deprovision NLB and its SGroups
resource "time_sleep" "ingress_dependencies" {
  depends_on = [
    module.eks_addons,
    aws_eip.lb
  ]

  destroy_duration = "2m"
}
