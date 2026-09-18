resource "helm_release" "loki" {
  name       = "loki"
  repository = "https://grafana.github.io/helm-charts"
  chart      = "loki"
  namespace  = kubernetes_namespace.monitoring.metadata[0].name
  version    = "~> 6.6"

  timeout = 600

  values = [
    yamlencode({
      deploymentMode = "SingleBinary"

      # Let the chart create AND own its ServiceAccount. Terraform
      # only supplies what the workload-identity webhook needs to
      # see on it — the client-id annotation naming which identity
      # to federate as, and the label telling the webhook to act
      # on this ServiceAccount at all. The reference to
      # azurerm_user_assigned_identity.workload["loki"] creates an
      # IMPLICIT dependency edge, so no depends_on is needed here.
      serviceAccount = {
        create = true
        name   = "loki"
        annotations = {
          "azure.workload.identity/client-id" = azurerm_user_assigned_identity.workload["loki"].client_id
        }
        labels = {
          "azure.workload.identity/use" = "true"
        }
      }

      loki = {
        # Loki's own auth is disabled here — Grafana reaches it
        # over the cluster-internal network only, no external
        # exposure, same trust model as Thanos Query.
        auth_enabled = false

        # The chart's default (3) assumes a multi-instance ring —
        # its own single-binary-values.yaml example sets this to 1
        # for exactly this deployment mode. Left at 3 with only ONE
        # singleBinary replica, the ring can never reach quorum:
        # every read fails with "too many unhealthy instances in
        # the ring", because 2 of the 3 expected replicas simply
        # don't exist.
        commonConfig = {
          replication_factor = 1
        }
        storage = {
          type = "azure"
          azure = {
            accountName = azurerm_storage_account.obs.name
            # NO accountKey field. Same story as Thanos — the
            # federated identity token is what authenticates,
            # discovered automatically by Loki's Azure SDK client
            # from the env vars the workload-identity webhook
            # injects into the pod.
            useFederatedToken = true
          }
          bucketNames = {
            chunks = azurerm_storage_container.loki_chunks.name
            ruler  = azurerm_storage_container.loki_ruler.name
          }
        }

        schemaConfig = {
          configs = [{
            from         = "2024-01-01"
            store        = "tsdb"
            object_store = "azure"
            schema       = "v13"
            index = {
              prefix = "loki_index_"
              period = "24h"
            }
          }]
        }

        limits_config = {
          retention_period = "168h" # 7 days — a PoC-scale bound,
          # same reasoning as Prometheus's
          # 6h local retention in Part 5:
          # keep the running footprint small
        }
      }

      singleBinary = {
        replicas = 1
        resources = {
          requests = { cpu = "150m", memory = "512Mi" }
          limits   = { memory = "1Gi" }
        }
        persistence = {
          size         = "5Gi"
          storageClass = "managed-csi"
        }
        # The workload-identity webhook mutates pods based on the
        # POD's own label, not the ServiceAccount's — serviceAccount
        # .labels above only tags the SA object. Without this label
        # here too, Loki starts with no Azure credentials injected
        # and panics building its ruler storage client.
        podLabels = {
          "azure.workload.identity/use" = "true"
        }
      }

      # The chart's own defaults set read/write/backend replicas to
      # 3 each, for the SimpleScalable topology we are NOT using.
      # With deploymentMode = "SingleBinary" but these left at their
      # defaults, the chart's validate.yaml sees both topologies
      # configured with replicas > 0 and refuses to install. Zeroing
      # them out is what SingleBinary mode actually requires.
      read = {
        replicas = 0
      }
      write = {
        replicas = 0
      }
      backend = {
        replicas = 0
      }

      # These are Loki's OWN internal caching/canary components,
      # not the Prometheus stack's — disabled for the same node-
      # budget reason as storegateway/compactor in Part 6.
      gateway = { enabled = false }
      test    = { enabled = false }
      monitoring = {
        selfMonitoring = { enabled = false }
      }

      # lokiCanary is a TOP-LEVEL key, not nested under 'monitoring'
      # — same class of mistake as serviceAccount's wrong nesting
      # above. Left nested, this silently does nothing and the
      # canary keeps running (harmless, but not what was intended).
      lokiCanary = { enabled = false }

      # The chart's default chunksCache.allocatedMemory (8192MB)
      # produces a ~9.6Gi memory REQUEST for the memcached pod —
      # more than this cluster's entire per-node allocatable memory
      # (~5.9Gi on a D2ds_v6). That pod can never schedule, which
      # then times out the whole helm_release since the provider
      # waits for every resource to become ready. Trimmed to fit
      # the same node budget as everything else here.
      chunksCache = {
        allocatedMemory = 512
      }
    })
  ]
}


# The chart's own single-binary Service template hardcodes
# `spec.type: ClusterIP` — it reads singleBinary.service.labels and
# .annotations, but never a .type field at all (confirmed against
# the chart source; the ONLY Service in this chart that honors a
# configurable type is the gateway's, which is disabled here). So
# setting singleBinary.service.type in the helm values above would
# be silently ignored, same failure class as every workload-identity
# label bug already hit in this file. A standalone Service, same
# pattern as kubernetes_service.thanos_query, is what actually
# exposes Loki on an internal IP — reachable from Alloy in aks-app
# across the VNet peering, where the ClusterIP DNS name Grafana uses
# doesn't resolve at all (ClusterIPs don't cross cluster boundaries).
resource "kubernetes_service" "loki_lb" {
  metadata {
    name      = "loki-lb"
    namespace = kubernetes_namespace.monitoring.metadata[0].name
    annotations = {
      "service.beta.kubernetes.io/azure-load-balancer-internal" = "true"
    }
  }

  spec {
    type     = "LoadBalancer"
    selector = { "app.kubernetes.io/name" = "loki", "app.kubernetes.io/instance" = "loki", "app.kubernetes.io/component" = "single-binary" }

    port {
      name        = "http-metrics"
      port        = 3100
      target_port = "http-metrics"
    }
    port {
      name        = "grpc"
      port        = 9095
      target_port = "grpc"
    }
  }
}
