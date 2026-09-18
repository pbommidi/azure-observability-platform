# ─────────────────────────────────────────────────────────────
# THANOS QUERY
#   A single stateless binary — no PVC, no StatefulSet needed.
#   Fans out to every Prometheus sidecar's StoreAPI via the
#   Operator's headless service, deduplicates on `replica`,
#   and exposes one unified PromQL endpoint for Grafana.
#
#   Same maintained image as the sidecar (quay.io/thanos), not
#   the Bitnami chart's own image — avoids depending on two
#   different upstreams for one system.
# ─────────────────────────────────────────────────────────────

resource "kubernetes_deployment" "thanos_query" {
  metadata {
    name      = "thanos-query"
    namespace = kubernetes_namespace.monitoring.metadata[0].name
    labels    = { app = "thanos-query" }
  }

  spec {
    replicas = 1

    selector {
      match_labels = { app = "thanos-query" }
    }

    template {
      metadata {
        labels = { app = "thanos-query" }
      }

      spec {
        container {
          name  = "thanos-query"
          image = "quay.io/thanos/thanos:v0.36.1"

          args = [
            "query",
            "--http-address=0.0.0.0:9090",
            "--grpc-address=0.0.0.0:10901",

            # dns+ resolves every pod IP behind the headless service —
            # this is what reaches BOTH Prometheus sidecars through
            # one line, rather than hardcoding two addresses.
            "--endpoint=dns+prometheus-operated.monitoring.svc.cluster.local:10901",

            # THE line that makes deduplication real — reads the
            # replica label set in Part 5, merges series that match
            # on every OTHER label, strips this one from the output.
            "--query.replica-label=replica",
          ]

          port {
            name           = "http"
            container_port = 9090
          }
          port {
            name           = "grpc"
            container_port = 10901
          }

          resources {
            requests = { cpu = "100m", memory = "256Mi" }
            limits   = { memory = "512Mi" }
          }

          readiness_probe {
            http_get {
              path = "/-/ready"
              port = 9090
            }
            initial_delay_seconds = 5
            period_seconds        = 10
          }
        }
      }
    }
  }

  # Same reasoning as Part 5's helm_release timeout — waiting on a
  # real readiness probe, not just "container started."
  wait_for_rollout = true
  timeouts {
    create = "5m"
  }

  depends_on = [helm_release.prometheus]
}


resource "kubernetes_service" "thanos_query" {
  metadata {
    name      = "thanos-query"
    namespace = kubernetes_namespace.monitoring.metadata[0].name
  }

  spec {
    selector = { app = "thanos-query" }

    port {
      name        = "http"
      port        = 9090
      target_port = 9090
    }
    port {
      name        = "grpc"
      port        = 10901
      target_port = 10901
    }
  }
}
