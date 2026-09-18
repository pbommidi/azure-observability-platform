resource "kubernetes_namespace" "app_monitoring" {
  provider = kubernetes.app

  metadata {
    name = "monitoring"
  }
}


resource "helm_release" "alloy" {
  provider = helm.app

  name       = "alloy"
  repository = "https://grafana.github.io/helm-charts"
  chart      = "alloy"
  namespace  = kubernetes_namespace.app_monitoring.metadata[0].name
  version    = "~> 0.11"

  timeout = 300

  values = [
    yamlencode({
      alloy = {
        configMap = {
          create  = true
          content = <<-EOT
            prometheus.scrape "node_metrics" {
              targets = [{
                __address__ = "localhost:12345",
              }]
              forward_to = [prometheus.remote_write.to_prometheus.receiver]
            }

            prometheus.remote_write "to_prometheus" {
              endpoint {
                // Same reason as Loki/Tempo below: ClusterIP DNS from
                // aks-mon doesn't resolve inside aks-app — these are
                // two separate clusters, not one. 10.20.0.8 is the
                // internal LoadBalancer IP Azure assigned to
                // kube-prometheus-kube-prome-prometheus in aks-mon,
                // confirmed via kubectl, not assumed from the
                // .6/.7/.8 pattern of the other two.
                url = "http://10.20.0.8:9090/api/v1/write"
              }
            }

            discovery.kubernetes "pods" {
              role = "pod"
            }

            loki.source.kubernetes "pod_logs" {
              targets    = discovery.kubernetes.pods.targets
              forward_to = [loki.write.to_loki.receiver]
            }

            loki.write "to_loki" {
              endpoint {
                url = "http://10.20.0.6:3100/loki/api/v1/push"
              }
            }

            otelcol.receiver.otlp "otlp_receiver" {
              grpc {
                endpoint = "0.0.0.0:4317"
              }
              http {
                endpoint = "0.0.0.0:4318"
              }
              output {
                traces = [otelcol.exporter.otlp.to_tempo.input]
              }
            }

            otelcol.exporter.otlp "to_tempo" {
              client {
                endpoint = "10.20.0.7:4317"
                tls {
                  insecure = true
                }
              }
            }
          EOT
        }
      }
    })
  ]
}


resource "kubernetes_service" "alloy_otlp" {
  provider = kubernetes.app
  metadata {
    name      = "alloy-otlp"
    namespace = kubernetes_namespace.app_monitoring.metadata[0].name
  }
  spec {
    selector = {
      "app.kubernetes.io/name" = "alloy"
    }
    port {
      name        = "otlp-grpc"
      port        = 4317
      target_port = 4317
    }
    type = "ClusterIP"
  }
}
