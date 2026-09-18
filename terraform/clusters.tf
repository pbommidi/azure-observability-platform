# ─────────────────────────────────────────────────────────────
# MONITORING CLUSTER
#   Hosts Prometheus HA, Thanos, Loki, Tempo and Grafana.
#   Built first in the file, though Terraform creates both in
#   parallel — nothing here references the other cluster.
# ─────────────────────────────────────────────────────────────

resource "azurerm_kubernetes_cluster" "mon" {
  name                = "aks-mon"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  # Becomes part of the cluster's API server FQDN. Must be unique
  # within the region, so prefixing with the cluster name is enough.
  dns_prefix = "aks-mon"

  kubernetes_version = var.kubernetes_version

  # Free has no uptime SLA on the control plane. Irrelevant for a
  # PoC and saves roughly $0.10/hr per cluster.
  sku_tier = "Free"

  # ── The system node pool ────────────────────────────────────
  # Every AKS cluster needs one. It runs CoreDNS, metrics-server,
  # konnectivity and the CSI drivers alongside your workloads.
  default_node_pool {
    name       = "system"
    node_count = var.node_count
    vm_size    = var.node_size

    # THE LINE THAT TIES THIS TO PART 1. Referencing the subnet's
    # id creates the dependency edge — this is why we never write
    # depends_on.
    vnet_subnet_id = azurerm_subnet.mon_aks.id

    # Local NVMe on the v6 family is faster and cheaper than a
    # managed OS disk, and node disks are disposable anyway.
    os_disk_type    = "Ephemeral"
    os_disk_size_gb = 100

    # Spread nodes across availability zones. Costs nothing and
    # means a single zone failure does not take the cluster down.
    # zones = ["1", "2"]
  }

  # ── Identity ────────────────────────────────────────────────
  # Azure creates and manages an identity for the cluster to call
  # Azure APIs with — creating load balancers, attaching disks.
  # This is the cluster's OWN identity, distinct from the workload
  # identity we grant to pods in Part 4.
  identity {
    type = "SystemAssigned"
  }

  # ── Networking ──────────────────────────────────────────────
  network_profile {
    # Azure CNI with overlay: NODES get IPs from your subnet,
    # PODS get IPs from a separate overlay range. Your /20 stays
    # almost empty, and pod density is not limited by subnet size.
    network_plugin      = "azure"
    network_plugin_mode = "overlay"

    # The overlay range. Internal to the cluster, never routed
    # outside it, so the same range on both clusters is fine —
    # but keeping them distinct avoids confusion when debugging.
    pod_cidr = "10.244.0.0/16"

    # Virtual IPs for Kubernetes Services. Must not overlap the
    # VNet or the pod CIDR.
    service_cidr   = "172.16.0.0/16"
    dns_service_ip = "172.16.0.10"

    # Outbound internet for nodes, via a load balancer Azure
    # manages. This is what replaces the workshop's NAT gateways.
    outbound_type     = "loadBalancer"
    load_balancer_sku = "standard"
  }

  # ── Workload identity, enabled now ──────────────────────────
  # Part 4 grants pods access to blob storage using these. They
  # CANNOT be enabled later without a cluster update, so turning
  # them on at creation avoids a rebuild.
  oidc_issuer_enabled       = true
  workload_identity_enabled = true

  tags = var.tags
}


# ─────────────────────────────────────────────────────────────
# APPLICATION CLUSTER
#   Hosts the workload being observed, plus the Alloy agent that
#   collects its telemetry and ships it across the peering.
# ─────────────────────────────────────────────────────────────

resource "azurerm_kubernetes_cluster" "app" {
  name                = "aks-app"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  dns_prefix          = "aks-app"
  kubernetes_version  = var.kubernetes_version
  sku_tier            = "Free"

  default_node_pool {
    name            = "system"
    node_count      = var.node_count
    vm_size         = var.node_size
    vnet_subnet_id  = azurerm_subnet.app_aks.id
    os_disk_type    = "Ephemeral"
    os_disk_size_gb = 100
    #zones           = ["1", "2"]
  }

  identity {
    type = "SystemAssigned"
  }

  network_profile {
    network_plugin      = "azure"
    network_plugin_mode = "overlay"

    # Deliberately DIFFERENT from the monitoring cluster. Overlay
    # ranges are cluster-internal so they could overlap safely,
    # but distinct ranges make packet captures unambiguous.
    pod_cidr = "10.245.0.0/16"

    service_cidr   = "172.17.0.0/16"
    dns_service_ip = "172.17.0.10"

    outbound_type     = "loadBalancer"
    load_balancer_sku = "standard"
  }

  oidc_issuer_enabled       = true
  workload_identity_enabled = true

  tags = var.tags
}
