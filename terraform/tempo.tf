# ─────────────────────────────────────────────────────────────
# TEMPO — ServiceAccount + Helm release
#   No ring, no replication_factor, no SingleBinary/Distributed
#   topology choice — this chart has none of Loki's multi-mode
#   complexity. One Deployment, one job: store traces keyed by
#   trace_id, indexed on almost nothing else.
# ─────────────────────────────────────────────────────────────

resource "helm_release" "tempo" {
  name       = "tempo"
  repository = "https://grafana.github.io/helm-charts"
  chart      = "tempo"
  namespace  = kubernetes_namespace.monitoring.metadata[0].name
  version    = "~> 1.10"

  timeout = 600

  values = [
    yamlencode({
      # Confirmed top-level shape, identical to Loki's chart —
      # let the chart own and create its ServiceAccount, we only
      # supply the two signals the workload-identity webhook needs.
      serviceAccount = {
        create = true
        name   = "tempo"
        annotations = {
          "azure.workload.identity/client-id" = azurerm_user_assigned_identity.workload["tempo"].client_id
        }
        labels = {
          "azure.workload.identity/use" = "true"
        }
      }

      # serviceAccount.labels above only tags the SA object — the
      # webhook mutates pods based on the POD's own label (same bug
      # class hit on Loki and Prometheus). This chart's StatefulSet
      # reads podLabels as a TOP-LEVEL key, not nested under tempo.
      # Without this, the pod gets no AZURE_CLIENT_ID/token, and
      # Tempo's usage-report module — which exercises the configured
      # storage backend at startup — fails to build an Azure client
      # at all, surfacing as the unrelated-looking
      # "getting storage container: open : no such file or directory".
      podLabels = {
        "azure.workload.identity/use" = "true"
      }

      tempo = {
        storage = {
          trace = {
            backend = "azure"
            azure = {
              container_name       = azurerm_storage_container.tempo.name
              storage_account_name = azurerm_storage_account.obs.name
              # NOT use_managed_identity — that's the node/pod system
              # identity path. This is the one that consumes the
              # federated OIDC token from the ServiceAccount above,
              # matching Thanos's msi_resource and Loki's
              # useFederatedToken mechanism.
              use_federated_token = true
            }
          }
        }

        # 72h — shorter than Loki's 7 days, since traces are far
        # higher volume per byte of "useful information" than logs,
        # and this is a PoC with a fixed node budget.
        retention = "72h"

        resources = {
          requests = { cpu = "100m", memory = "256Mi" }
          limits   = { memory = "512Mi" }
        }
      }

      persistence = {
        enabled          = true
        size             = "5Gi"
        storageClassName = "managed-csi"
      }

      # Unlike Loki's single-binary Service, this chart's own
      # templates/service.yaml DOES read service.type — confirmed
      # against the chart source, LoadBalancer is a real, wired
      # branch here. Internal so it's only reachable from within the
      # peered VNet (Alloy in aks-app), never from the internet.
      service = {
        type = "LoadBalancer"
        annotations = {
          "service.beta.kubernetes.io/azure-load-balancer-internal" = "true"
        }
      }
    })
  ]
}
