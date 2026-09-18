# ─────────────────────────────────────────────────────────────
# STORAGE ACCOUNT
#   One account, four containers. This is Azure's structure —
#   S3 gives you N independent buckets; Azure gives you one
#   account containing N containers. Neither is more "correct",
#   but it changes how you think about blast radius: compromising
#   the ACCOUNT key would expose everything, which is exactly why
#   we never use the account key and rely on per-container RBAC
#   instead.
# ─────────────────────────────────────────────────────────────

resource "random_string" "storage_suffix" {
  length  = 6
  special = false
  upper   = false
  # Storage account names must be globally unique across ALL of
  # Azure, lowercase alphanumeric only, 3-24 characters. A random
  # suffix avoids a naming collision with someone else's account.
}


resource "azurerm_storage_account" "obs" {
  name                = "stobsday2${random_string.storage_suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location

  account_tier             = "Standard"
  account_replication_type = "LRS" # locally redundant — cheapest,
  # fine for a PoC. GRS replicates
  # cross-region for production.

  min_tls_version = "TLS1_2"

  # CRITICAL: leaving this at its default (false) is what we want.
  # true enables hierarchical namespace (Data Lake Gen2), which
  # changes how Thanos/Loki/Tempo address blobs and breaks their
  # S3-compatible client libraries. This has bitten people badly
  # enough that it is worth a comment, not just a default.
  is_hns_enabled = false

  tags = var.tags
}


resource "azurerm_storage_container" "thanos" {
  name                  = "thanos"
  storage_account_id    = azurerm_storage_account.obs.id
  container_access_type = "private"
}


resource "azurerm_storage_container" "loki_chunks" {
  name                  = "loki-chunks"
  storage_account_id    = azurerm_storage_account.obs.id
  container_access_type = "private"
}


resource "azurerm_storage_container" "loki_ruler" {
  name                  = "loki-ruler"
  storage_account_id    = azurerm_storage_account.obs.id
  container_access_type = "private"
}


resource "azurerm_storage_container" "tempo" {
  name                  = "tempo-traces"
  storage_account_id    = azurerm_storage_account.obs.id
  container_access_type = "private"
}
