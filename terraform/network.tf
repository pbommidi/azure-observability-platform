# The container for everything in Day 2. Kept separate from
# rg-obs-lab so Terraform owns everything it creates, and nothing
# it did not create.
resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name
  location = var.location
  tags     = var.tags
}


# ─────────────────────────────────────────────────────────────
# APPLICATION NETWORK
#   Hosts the workload being observed: Online Boutique and the
#   Alloy collection agent. Deliberately separate from monitoring
#   so the telemetry path between them is explicit.
# ─────────────────────────────────────────────────────────────

resource "azurerm_virtual_network" "app" {
  name                = "vnet-app"
  address_space       = [var.app_vnet_cidr]
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = var.tags
}


resource "azurerm_subnet" "app_aks" {
  name                 = "snet-app-aks"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.app.name
  address_prefixes     = [var.app_subnet_cidr]
}


# ─────────────────────────────────────────────────────────────
# MONITORING NETWORK
#   Hosts Prometheus, Thanos, Loki, Tempo and Grafana.
# ─────────────────────────────────────────────────────────────

resource "azurerm_virtual_network" "mon" {
  name                = "vnet-mon"
  address_space       = [var.mon_vnet_cidr]
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = var.tags
}


resource "azurerm_subnet" "mon_aks" {
  name                 = "snet-mon-aks"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.mon.name
  address_prefixes     = [var.mon_subnet_cidr]
}


# ─────────────────────────────────────────────────────────────
# VNET PEERING
#   Azure models a peering as a property of EACH network, so two
#   resources are required. Create only one and the link sits in
#   'Initiated' state carrying no traffic — it exists, the portal
#   shows it, and nothing flows.
#
#   This is the ONLY path between the two networks. Alloy in the
#   application VNet reaches Loki, Tempo and Prometheus in the
#   monitoring VNet across this link.
# ─────────────────────────────────────────────────────────────

resource "azurerm_virtual_network_peering" "app_to_mon" {
  name                      = "app-to-mon"
  resource_group_name       = azurerm_resource_group.main.name
  virtual_network_name      = azurerm_virtual_network.app.name
  remote_virtual_network_id = azurerm_virtual_network.mon.id

  # Traffic may flow from app to mon.
  allow_virtual_network_access = true

  # Allows resolving private DNS across the peering. The workshop
  # does the same with AllowDnsResolutionFromRemoteVpc, and it is
  # what lets Alloy target a service name rather than a raw IP.
  allow_forwarded_traffic = true
}


resource "azurerm_virtual_network_peering" "mon_to_app" {
  name                      = "mon-to-app"
  resource_group_name       = azurerm_resource_group.main.name
  virtual_network_name      = azurerm_virtual_network.mon.name
  remote_virtual_network_id = azurerm_virtual_network.app.id

  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
}
