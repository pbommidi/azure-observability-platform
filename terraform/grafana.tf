resource "random_password" "grafana_admin" {
  length  = 24
  special = true
}


resource "kubernetes_secret" "grafana_admin" {
  metadata {
    name      = "grafana-admin-credentials"
    namespace = kubernetes_namespace.monitoring.metadata[0].name
  }

  data = {
    admin-user     = "admin"
    admin-password = random_password.grafana_admin.result
  }
}


resource "helm_release" "grafana" {
  name       = "grafana"
  repository = "https://grafana.github.io/helm-charts"
  chart      = "grafana"
  namespace  = kubernetes_namespace.monitoring.metadata[0].name
  version    = "~> 8.5"

  timeout = 300

  values = [
    yamlencode({
      # Points at the Secret rather than putting a password in
      # values — the chart reads both keys from it directly.
      admin = {
        existingSecret = kubernetes_secret.grafana_admin.metadata[0].name
        userKey        = "admin-user"
        passwordKey    = "admin-password"
      }

      # PROVISIONING — same principle as your Day 1 Chapter 7.
      # A declared datasource, not a clicked one, so it survives
      # a pod restart and is something worth testing against.
      datasources = {
        "datasources.yaml" = {
          apiVersion = 1
          datasources = [
            {
              name = "Thanos"
              type = "prometheus"
              # Pinned UID — same reasoning as Day 1: dashboard
              # JSON references this by UID, and a generated one
              # breaks every dashboard on a rebuild.
              uid       = "thanos"
              access    = "proxy"
              url       = "http://thanos-query.monitoring.svc.cluster.local:9090"
              isDefault = true
              editable  = false
            },
            {
              name      = "Loki"
              type      = "loki"
              uid       = "loki"
              access    = "proxy"
              url       = "http://loki.monitoring.svc.cluster.local:3100"
              isDefault = false
              editable  = false
            },
            {
              name      = "Tempo"
              type      = "tempo"
              uid       = "tempo"
              access    = "proxy"
              url       = "http://tempo.monitoring.svc.cluster.local:3100"
              isDefault = false
              editable  = false
            }
          ]
        }
      }

      persistence = {
        # A PoC choice, stated plainly: dashboards created through
        # the UI vanish if this pod is rescheduled. Fine for now —
        # anything worth keeping should be provisioned as code
        # anyway, same argument as the datasource itself.
        enabled = false
      }

      resources = {
        requests = { cpu = "100m", memory = "128Mi" }
        limits   = { memory = "256Mi" }
      }

      service = {
        type = "LoadBalancer"
      }
    })
  ]

  depends_on = [kubernetes_deployment.thanos_query]
}
