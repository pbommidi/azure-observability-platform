resource "kubernetes_namespace" "monitoring" {
  metadata {
    name = "monitoring"
  }
}


resource "helm_release" "prometheus" {
  name       = "kube-prometheus"
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "kube-prometheus-stack"
  namespace  = kubernetes_namespace.monitoring.metadata[0].name
  version    = "~> 65.0"

  # Give it time — the chart creates CRDs, then a StatefulSet with
  # PVCs that must bind before the pods report ready.
  timeout = 600

  values = [
    yamlencode({
      prometheus = {
        # The chart NEVER reads prometheusSpec.serviceAccountName —
        # its CR template hardcodes serviceAccountName to whatever
        # this helper resolves to. Pointing it at the pre-existing
        # "thanos" ServiceAccount (create = false) is what actually
        # makes the sidecar run under Thanos's federated identity;
        # the chart's own ClusterRoleBinding still binds Prometheus's
        # scrape-discovery RBAC to this same name either way.
        serviceAccount = {
          create = false
          name   = kubernetes_service_account.thanos.metadata[0].name
        }

        prometheusSpec = {
          replicas                 = 2
          replicaExternalLabelName = "replica"

          # The Azure workload-identity webhook mutates pods based on
          # the POD's own label, not the ServiceAccount's — same class
          # of bug fixed for Loki. podMetadata is the Operator's own
          # mechanism for adding labels to the generated Prometheus
          # pods; without this the sidecar has no client-id/token
          # injected and any Azure call falls back to the AKS node's
          # own identity (a clean 403, not a credential error).
          podMetadata = {
            labels = {
              "azure.workload.identity/use" = "true"
            }
          }

          # Local retention is short on purpose. Once Thanos ships
          # blocks to blob storage in Part 6, Prometheus itself only
          # needs to hold a small recent window.
          retention = "6h"

          # Opens /api/v1/write so Alloy (and anything else) can push
          # samples directly, rather than Prometheus only ever pulling
          # via its own scrape configs. Off by default — this endpoint
          # accepts writes from anything that can reach it: not
          # authenticated, not scoped to Alloy specifically. Inside a
          # private cluster network with no external exposure, that's
          # an acceptable risk for a PoC — the same category of note
          # as Loki's auth_enabled = false. Would need real hardening
          # (NetworkPolicy at minimum, ideally mTLS/auth in front of
          # it) before this goes anywhere near production.
          enableRemoteWriteReceiver = true

          storageSpec = {
            volumeClaimTemplate = {
              spec = {
                storageClassName = "managed-csi"
                accessModes      = ["ReadWriteOnce"]
                resources = {
                  requests = { storage = "10Gi" }
                }
              }
            }
          }

          # Trimmed for our node budget — see Part 5 sizing note below.
          resources = {
            requests = { cpu = "250m", memory = "1Gi" }
            limits   = { memory = "2Gi" }
          }

          thanos = {
            image = "quay.io/thanos/thanos:v0.36.1"

            # The chart's own template explicitly OMITS whatever raw
            # objectStorageConfig you pass here (see
            # templates/prometheus/prometheus.yaml: `omit ... thanos
            # "objectStorageConfig"`), and rebuilds it ONLY from this
            # existingSecret shape — a flat secretName/key map here
            # is silently dropped entirely, which is why the CR ended
            # up with no objectStorageConfig at all and the sidecar
            # logged "no supported bucket was configured".
            objectStorageConfig = {
              existingSecret = {
                name = "thanos-objstore-config"
                key  = "objstore.yml"
              }
            }
          }
        }

        # Prometheus's own Service, confirmed against the real
        # template (templates/prometheus/service.yaml) to honor both
        # `type` and `annotations` genuinely, via a literal
        # `type: "{{ .Values.prometheus.service.type }}"` at the end
        # of the spec — unlike Loki's singleBinary.service.type,
        # which that chart's template ignores outright. Internal so
        # it's only reachable from the peered VNet (Alloy in
        # aks-app), never the internet.
        service = {
          type = "LoadBalancer"
          annotations = {
            "service.beta.kubernetes.io/azure-load-balancer-internal" = "true"
          }
        }
      }

      # Grafana ships bundled in this chart. We disable it here and
      # install our own in Part 7 with the settings we actually want.
      grafana = { enabled = false }

      # Alertmanager is out of scope for Day 2 — not in the workshop's
      # Day 2 either.
      alertmanager = { enabled = false }
    })
  ]
}


# This ServiceAccount is what Part 4's federated credential trusts.
# The subject string there was:
#   system:serviceaccount:monitoring:thanos
# which is EXACTLY namespace + name of this object. If either
# changes, the federation silently stops matching — same failure
# mode we discussed in Part 4's knowledge check.
resource "kubernetes_service_account" "thanos" {
  metadata {
    name      = "thanos"
    namespace = kubernetes_namespace.monitoring.metadata[0].name

    annotations = {
      # This is what triggers the azure-wi-webhook (visible running
      # in your pod list since Part 2) to inject the AZURE_CLIENT_ID
      # and token file env vars into any pod using this ServiceAccount.
      "azure.workload.identity/client-id" = azurerm_user_assigned_identity.workload["thanos"].client_id
    }

    labels = {
      # The webhook only acts on pods carrying this label. Annotation
      # alone is not enough — both are required.
      "azure.workload.identity/use" = "true"
    }
  }
}


resource "kubernetes_secret" "thanos_objstore" {
  metadata {
    name      = "thanos-objstore-config"
    namespace = kubernetes_namespace.monitoring.metadata[0].name
  }

  data = {
    "objstore.yml" = yamlencode({
      type = "AZURE"
      config = {
        storage_account = azurerm_storage_account.obs.name
        container       = azurerm_storage_container.thanos.name
        # NO storage_account_key HERE. Authentication happens via
        # the pod's federated identity token — the Azure SDK inside
        # Thanos discovers AZURE_CLIENT_ID and the token file from
        # env vars the webhook injected, with no key in this file
        # at all. This is the direct payoff of Part 4.
        msi_resource = ""
      }
    })
  }
}
