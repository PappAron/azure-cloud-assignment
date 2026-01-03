# 1. Create a Resource Group
resource "azurerm_resource_group" "project_rg" {
  name     = "cloud-native-assignment-rg"
  location = "uksouth"
}

# 2. Create the AKS Cluster
resource "azurerm_kubernetes_cluster" "aks" {
  name                = "online-boutique-cluster"
  location            = azurerm_resource_group.project_rg.location
  resource_group_name = azurerm_resource_group.project_rg.name
  dns_prefix          = "boutique-k8s"

default_node_pool {
    name       = "default"
    node_count = 2
    vm_size    = "Standard_B2s" 
    os_disk_type = "Managed"
  }

  # Managed Identity is the modern cloud-native way to handle permissions
  identity {
    type = "SystemAssigned"
  }

  tags = {
    Environment = "SemesterTask"
  }
}

# 3. Output the Kube Config (This is what you'll use to connect to the cluster)
output "kube_config" {
  value     = azurerm_kubernetes_cluster.aks.kube_config_raw
  sensitive = true
}

# 4. Create Azure Cache for Redis (Managed Database)
resource "azurerm_redis_cache" "cart_db" {
  name                = "boutique-cart-db-${random_integer.ri.result}" # Needs a unique name
  location            = azurerm_resource_group.project_rg.location
  resource_group_name = azurerm_resource_group.project_rg.name
  capacity            = 0
  family              = "C"
  sku_name            = "Basic" # Cheapest option for students
  enable_non_ssl_port = true
}

# Generate a random integer to ensure the Redis name is globally unique
resource "random_integer" "ri" {
  min = 10000
  max = 99999
}

# Output the Redis Hostname so we can use it in the app
output "redis_hostname" {
  value = azurerm_redis_cache.cart_db.hostname
}

# 5. Create the Container Registry
resource "azurerm_container_registry" "acr" {
  name                = "boutiqueregistry${random_integer.ri.result}"
  resource_group_name = azurerm_resource_group.project_rg.name
  location            = azurerm_resource_group.project_rg.location
  sku                 = "Basic"
  admin_enabled       = true
}

# Give AKS permission to 'pull' images from this registry
resource "azurerm_role_assignment" "aks_acr_pull" {
  principal_id                     = azurerm_kubernetes_cluster.aks.kubelet_identity[0].object_id
  role_definition_name             = "AcrPull"
  scope                            = azurerm_container_registry.acr.id
  skip_service_principal_aad_check = true
}

output "acr_name" {
  value = azurerm_container_registry.acr.name
}