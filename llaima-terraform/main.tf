# Grupo de recursos
resource "azurerm_resource_group" "rg" {
  name     = var.resource_group_name_prefix
  location = var.resource_group_location
}

# Red Virtual
resource "azurerm_virtual_network" "vnet" {
  name                = "aks-llaima-vnet"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  address_space       = ["10.0.0.0/16"]
}

# Subred
resource "azurerm_subnet" "subnet" {
  name                 = "aks-llaima-subnet"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.1.0/24"]
}

# Clúster de Kubernetes
resource "azurerm_kubernetes_cluster" "aks" {
  name                 = "aks-llaima"
  location             = azurerm_resource_group.rg.location
  resource_group_name  = azurerm_resource_group.rg.name
  dns_prefix           = "aks-llaima-dns"
  azure_policy_enabled = true

  kubernetes_version = "1.29.0" 

  default_node_pool {
    name           = "default"
    node_count     = var.node_count
    vm_size        = "Standard_DS2_v2"
    vnet_subnet_id = azurerm_subnet.subnet.id
    upgrade_settings {
      max_surge = "1"
    }
  }

  identity {
    type = "SystemAssigned"
  }

  network_profile {
    network_plugin = "azure"
    service_cidr   = "10.1.0.0/16"  
    dns_service_ip = "10.1.0.10"    
  }

  linux_profile {
    admin_username = var.username
    ssh_key {
      key_data = tls_private_key.ssh_key.public_key_openssh
    }
  }
}


# Espacio de trabajo de Log Analytics
resource "azurerm_log_analytics_workspace" "workspace" {
  name                = "llaima-logs"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
}

# Registro de contenedores ACR
resource "azurerm_container_registry" "acr" {
  name                = "llaimaacr"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  sku                 = "Standard"
}

# Permisos del AKS al ACR
resource "azurerm_role_assignment" "acr_pull_for_aks" {
  scope                = azurerm_container_registry.acr.id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_kubernetes_cluster.aks.identity[0].principal_id
}

# Recurso de clave privada
resource "tls_private_key" "ssh_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

# Recurso de cuenta de almacenamiento
resource "azurerm_storage_account" "storage" {
  name                     = "llaimalogs"
  resource_group_name      = azurerm_resource_group.rg.name
  location                 = azurerm_resource_group.rg.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
}

# Recurso de grupo de seguridad de red
resource "azurerm_network_security_group" "nsg" {
  name                = "aks-nsg"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
}

# Asociación de grupo de seguridad de red a la subred
resource "azurerm_subnet_network_security_group_association" "subnet_nsg" {
  subnet_id                 = azurerm_subnet.subnet.id
  network_security_group_id = azurerm_network_security_group.nsg.id
}
