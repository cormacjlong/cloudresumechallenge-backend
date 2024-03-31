variable "logging_on" {
  type        = bool
  description = "Turning this on will create a Log Analytics Workspace and configure logging for resources."
  default     = false
}

variable "resource_id" {
  type        = string
  description = "The resource ID of the resource to enable logging on."
}

variable "law_id" {
  type        = string
  description = "The ID of the Log Analytics Workspace to send logs to."

}

# Get the logging categories for the resource
data "azurerm_monitor_diagnostic_categories" "diag_categories" {
  count       = var.logging_on ? 1 : 0
  resource_id = resource_id
}

resource "azurerm_monitor_diagnostic_setting" "diag_settings" {
  count                      = var.logging_on ? 1 : 0
  name                       = "diag-applied-by-terraform"
  target_resource_id         = resource_id
  log_analytics_workspace_id = law_id

  dynamic "enabled_log" {
    for_each = data.azurerm_monitor_diagnostic_categories.diag_categories[0].log_category_types
    content {
      category = enabled_log.value
    }
  }
  # Ignoring changes to the metric category
  lifecycle {
    ignore_changes = [
      metric
    ]
  }
}
