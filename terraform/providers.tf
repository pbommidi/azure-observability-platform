# Tells Terraform which providers this project needs and which
# versions are acceptable. Pinning a major version means a breaking
# provider release cannot silently change your infrastructure.
terraform {
  required_version = ">= 1.9"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
    kubernetes = { source = "hashicorp/kubernetes", version = "~> 2.32" }
    helm       = { source = "hashicorp/helm", version = "~> 2.16" }

  }
}


# Configures the provider. Credentials are NOT here — the azurerm
# provider reads the token that 'az login' already cached, the same
# mechanism DefaultAzureCredential uses in your pytest framework.
provider "azurerm" {
  features {}
}


provider "kubernetes" {
  host                   = azurerm_kubernetes_cluster.mon.kube_config[0].host
  cluster_ca_certificate = base64decode(azurerm_kubernetes_cluster.mon.kube_config[0].cluster_ca_certificate)
  client_certificate     = base64decode(azurerm_kubernetes_cluster.mon.kube_config[0].client_certificate)
  client_key             = base64decode(azurerm_kubernetes_cluster.mon.kube_config[0].client_key)
}


provider "helm" {
  kubernetes {
    host                   = azurerm_kubernetes_cluster.mon.kube_config[0].host
    cluster_ca_certificate = base64decode(azurerm_kubernetes_cluster.mon.kube_config[0].cluster_ca_certificate)
    client_certificate     = base64decode(azurerm_kubernetes_cluster.mon.kube_config[0].client_certificate)
    client_key             = base64decode(azurerm_kubernetes_cluster.mon.kube_config[0].client_key)
  }
}


# Every resource so far has used the DEFAULT (unaliased) kubernetes/
# helm provider above, which is pinned to aks-mon's kubeconfig.
# Provider configuration is fixed per provider block — there is no
# per-resource "which cluster" argument the way azurerm resource
# groups work — so reaching aks-app at all requires a second,
# explicitly-aliased pair, and every resource meant for aks-app must
# carry provider = kubernetes.app / provider = helm.app. Leaving that
# argument off, as the first draft of helm_release.alloy did, doesn't
# error — it silently installs into aks-mon instead.
provider "kubernetes" {
  alias                  = "app"
  host                   = azurerm_kubernetes_cluster.app.kube_config[0].host
  cluster_ca_certificate = base64decode(azurerm_kubernetes_cluster.app.kube_config[0].cluster_ca_certificate)
  client_certificate     = base64decode(azurerm_kubernetes_cluster.app.kube_config[0].client_certificate)
  client_key             = base64decode(azurerm_kubernetes_cluster.app.kube_config[0].client_key)
}


provider "helm" {
  alias = "app"
  kubernetes {
    host                   = azurerm_kubernetes_cluster.app.kube_config[0].host
    cluster_ca_certificate = base64decode(azurerm_kubernetes_cluster.app.kube_config[0].cluster_ca_certificate)
    client_certificate     = base64decode(azurerm_kubernetes_cluster.app.kube_config[0].client_certificate)
    client_key             = base64decode(azurerm_kubernetes_cluster.app.kube_config[0].client_key)
  }
}
