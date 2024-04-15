variable "targets_resource_id" {
  description = "(Required) The list of ID of an existing Resource on which to configure Diagnostic Settings. Changing this forces a new resource to be created."
  type        = list(string)
}

variable "log_analytics_workspace_id" {
  description = "(Required) Specifies the ID of a Log Analytics Workspace where Diagnostics Data should be sent."
  type        = string
}
