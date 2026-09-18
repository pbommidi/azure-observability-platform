# BRING-YOUR-OWN-VNET GOTCHA: node pool attachment at cluster-create
# time (vnet_subnet_id above) works with no role assignment at all,
# because AKS's own resource provider performs that association
# using its own first-party permissions during provisioning. But
# ONGOING runtime operations — specifically the in-cluster
# cloud-controller-manager provisioning a NEW internal LoadBalancer
# IP — go through the cluster's OWN SystemAssigned identity, which
# by default only holds Contributor on AKS's auto-generated node
# resource group (MC_...), not on rg-obs-day2 where this VNet
# actually lives. Without this, any internal LoadBalancer Service
# fails with a 403 AuthorizationFailed reading the subnet.
resource "azurerm_role_assignment" "mon_cluster_vnet" {
  scope                = azurerm_virtual_network.mon.id
  role_definition_name = "Network Contributor"
  principal_id         = azurerm_kubernetes_cluster.mon.identity[0].principal_id
}


# ─────────────────────────────────────────────────────────────
# WORKLOAD IDENTITIES
#   One per system. Each federated to exactly one Kubernetes
#   ServiceAccount, so a compromised pod can only reach its own
#   container.
# ─────────────────────────────────────────────────────────────

locals {
  # Which Kubernetes namespace/serviceaccount each identity trusts.
  # These strings must match EXACTLY what the Helm charts create
  # in Parts 6, 8, 9 — this is the most common real-world source
  # of "workload identity isn't working."
  workload_identities = {
    thanos = {
      namespace       = "monitoring"
      service_account = "thanos"
    }
    loki = {
      namespace       = "monitoring"
      service_account = "loki"
    }
    tempo = {
      namespace       = "monitoring"
      service_account = "tempo"
    }
  }
}


resource "azurerm_user_assigned_identity" "workload" {
  for_each = local.workload_identities

  name                = "id-${each.key}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  tags                = var.tags
}


resource "azurerm_federated_identity_credential" "workload" {
  for_each = local.workload_identities

  name                      = "fed-${each.key}"
  user_assigned_identity_id = azurerm_user_assigned_identity.workload[each.key].id

  # The cluster this trust applies to. Everything in Part 4 runs
  # in aks-mon.
  issuer  = azurerm_kubernetes_cluster.mon.oidc_issuer_url
  subject = "system:serviceaccount:${each.value.namespace}:${each.value.service_account}"

  # Fixed value Azure requires for this exchange. Not configurable.
  audience = ["api://AzureADTokenExchange"]
}


# Grants each identity read/write on ITS OWN container only —
# not the storage account, not the other containers.
resource "azurerm_role_assignment" "thanos_storage" {
  scope                = azurerm_storage_container.thanos.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_user_assigned_identity.workload["thanos"].principal_id
}


resource "azurerm_role_assignment" "loki_storage" {
  for_each = {
    chunks = azurerm_storage_container.loki_chunks.id
    ruler  = azurerm_storage_container.loki_ruler.id
  }

  scope                = each.value
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_user_assigned_identity.workload["loki"].principal_id
}


resource "azurerm_role_assignment" "tempo_storage" {
  scope                = azurerm_storage_container.tempo.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_user_assigned_identity.workload["tempo"].principal_id
}
