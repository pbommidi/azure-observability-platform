# Outputs are the declared interface of this configuration — the
# values other things are allowed to depend on. Everything else is
# an implementation detail that can change freely.

output "resource_group_name" {
  description = "Resource group holding the Day 2 environment."
  value       = azurerm_resource_group.main.name
}

output "location" {
  description = "Region every resource lives in."
  value       = azurerm_resource_group.main.location
}

output "app_subnet_id" {
  description = "Subnet the application AKS node pool attaches to. Consumed by the cluster definition in Part 2."
  value       = azurerm_subnet.app_aks.id
}

output "mon_subnet_id" {
  description = "Subnet the monitoring AKS node pool attaches to."
  value       = azurerm_subnet.mon_aks.id
}

output "network_summary" {
  description = "The address plan, for quick reference when debugging connectivity."
  value = {
    app_vnet   = tolist(azurerm_virtual_network.app.address_space)[0]
    app_subnet = azurerm_subnet.app_aks.address_prefixes[0]
    mon_vnet   = tolist(azurerm_virtual_network.mon.address_space)[0]
    mon_subnet = azurerm_subnet.mon_aks.address_prefixes[0]
  }
}

output "mon_cluster_name" {
  value = azurerm_kubernetes_cluster.mon.name
}

output "app_cluster_name" {
  value = azurerm_kubernetes_cluster.app.name
}

# The OIDC issuer URL. Part 4 uses this to federate a managed
# identity to a Kubernetes service account — the Azure equivalent
# of the workshop's IRSA setup.
output "mon_oidc_issuer_url" {
  value = azurerm_kubernetes_cluster.mon.oidc_issuer_url
}

output "app_oidc_issuer_url" {
  value = azurerm_kubernetes_cluster.app.oidc_issuer_url
}

# Contains credentials. Marking it sensitive redacts it from plan
# and apply output — but it is STILL in terraform.tfstate in plain
# text, which is why state is gitignored.
output "mon_kube_config" {
  value     = azurerm_kubernetes_cluster.mon.kube_config_raw
  sensitive = true
}

output "storage_account_name" {
  value = azurerm_storage_account.obs.name
}

output "thanos_identity_client_id" {
  description = "Set as azure.workload.identity/client-id on the Thanos ServiceAccount in Part 6."
  value       = azurerm_user_assigned_identity.workload["thanos"].client_id
}

output "loki_identity_client_id" {
  value = azurerm_user_assigned_identity.workload["loki"].client_id
}

output "tempo_identity_client_id" {
  value = azurerm_user_assigned_identity.workload["tempo"].client_id
}

output "grafana_admin_password" {
  value     = random_password.grafana_admin.result
  sensitive = true
}