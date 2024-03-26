variable "resource_location" {
  type        = string
  description = "Location of all resources."
  default     = "northeurope"
}

variable "project_prefix" {
  type        = string
  description = "This is a short prefix that relates to the project and will be added to all resource names."
  default     = "crc"
}

variable "env" {
  type        = string
  description = "The environment currently being deplyed."
  default     = "dev"
}

variable "custom_url_prefix" {
  type        = string
  description = "The custom URL prefix for the website."
  default     = "cv"
}

variable "azure_dns_zone_name" {
  type        = string
  description = "The name of the Azure DNS zone to create."
  default     = "az.macro-c.com"
}

variable "azure_dns_zone_resource_group_name" {
  type        = string
  description = "The name of the resource group the the Azure DNS zone is in."
  default     = "rg-dns"
}
