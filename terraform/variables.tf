variable "resource_location" {
  type        = string
  description = "Location of all resources."
  default     = "northeurope"
}

variable "project_prefix" {
  type        = list(string)
  description = "These are short prefix that relates to the project and will be added to all resource names."
  default     = ["crc", "back"]
}

variable "env" {
  type        = string
  description = "The environment currently being deployed."
  default     = "test"
}

variable "custom_url_prefix" {
  type        = string
  description = "The custom URL prefix for the website."
  default     = "cv"
}

variable "azure_dns_zone_name" {
  type        = string
  description = "The name of the Azure DNS zone."
  default     = "az.macro-c.com"
}

variable "azure_dns_zone_resource_group_name" {
  type        = string
  description = "The name of the resource group the the Azure DNS zone is in."
  default     = "rg-platform-connectivity"
}

variable "managed_identity_name" {
  type        = string
  description = "The name of the managed identity to retrieve."
  default     = "id-github-crc"
}

variable "mid_resource_group_name" {
  type        = string
  description = "The resource group of the managed identity to retrieve."
  default     = "rg-platform-identity"
}

variable "cosmos_table_name" {
  type        = string
  description = "The name of the CosmosDB table."
  default     = "VisitorCountTable"
}

variable "connection_string_secret_name" {
  type        = string
  description = "The name of the secret that holds the connection string."
  default     = "cosmosdb-connection-string"
}

variable "logging_on" {
  type        = bool
  description = "Turning this on will create a Log Analytics Workspace and configure logging for resources."
  default     = false
}

variable "api_endpoint_name" {
  type        = string
  description = "The suffix for the API URL."
  default     = "getvisitor"
}

variable "api_path" {
  type        = string
  description = "The path for the API."
  default     = "api"
}
