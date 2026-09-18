resource "kubernetes_config_map" "demo_app" {
  provider = kubernetes.app
  metadata {
    name      = "demo-app-src"
    namespace = kubernetes_namespace.app_monitoring.metadata[0].name
  }

  data = {
    "app.py" = <<-EOT
      import time, random, logging, sys
      from flask import Flask
      from opentelemetry import trace
      from opentelemetry.sdk.trace import TracerProvider
      from opentelemetry.sdk.trace.export import BatchSpanProcessor
      from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter
      from opentelemetry.sdk.resources import Resource

      logging.basicConfig(stream=sys.stdout, level=logging.INFO,
                           format='%(asctime)s %(levelname)s %(message)s')
      log = logging.getLogger("demo-app")

      resource = Resource.create({"service.name": "demo-app"})
      provider = TracerProvider(resource=resource)
      # Alloy's OTLP receiver, reached via the Service this part
      # also creates — cluster-internal DNS, same signal cluster
      # both the app and Alloy live in.
      exporter = OTLPSpanExporter(endpoint="alloy-otlp.monitoring.svc.cluster.local:4317", insecure=True)
      provider.add_span_processor(BatchSpanProcessor(exporter))
      trace.set_tracer_provider(provider)
      tracer = trace.get_tracer("demo-app")

      app = Flask(__name__)

      @app.route("/")
      def index():
          with tracer.start_as_current_span("handle-request") as span:
              delay = random.uniform(0.05, 0.3)
              time.sleep(delay)
              span.set_attribute("delay_seconds", delay)
              log.info(f"handled request in {delay:.3f}s")
              return {"status": "ok", "delay": delay}

      @app.route("/healthz")
      def health():
          return {"status": "ready"}

      if __name__ == "__main__":
          app.run(host="0.0.0.0", port=8080)
    EOT
  }
}


resource "kubernetes_deployment" "demo_app" {
  provider = kubernetes.app
  metadata {
    name      = "demo-app"
    namespace = kubernetes_namespace.app_monitoring.metadata[0].name
    labels    = { app = "demo-app" }
  }

  spec {
    replicas = 1
    selector { match_labels = { app = "demo-app" } }

    template {
      metadata { labels = { app = "demo-app" } }
      spec {
        container {
          name    = "demo-app"
          image   = "python:3.12-slim"
          command = ["sh", "-c"]
          args = [
            "pip install --no-cache-dir flask opentelemetry-sdk opentelemetry-exporter-otlp-proto-grpc >/dev/null 2>&1 && python /app/app.py"
          ]

          volume_mount {
            name       = "src"
            mount_path = "/app"
          }

          port { container_port = 8080 }

          resources {
            requests = { cpu = "50m", memory = "128Mi" }
            limits   = { memory = "256Mi" }
          }

          readiness_probe {
            http_get {
              path = "/healthz"
              port = 8080
            }
            initial_delay_seconds = 20
            period_seconds        = 10
          }
        }

        volume {
          name = "src"
          config_map { name = kubernetes_config_map.demo_app.metadata[0].name }
        }
      }
    }
  }
}


resource "kubernetes_service" "demo_app" {
  provider = kubernetes.app
  metadata {
    name      = "demo-app"
    namespace = kubernetes_namespace.app_monitoring.metadata[0].name
  }
  spec {
    selector = { app = "demo-app" }
    port {
      port        = 8080
      target_port = 8080
    }
    type = "ClusterIP"
  }
}
