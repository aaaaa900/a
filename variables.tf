variable "folders" {
  description = "List of folders"
  type = list(object({
    name   = string
    parent = string
    assured_workload_config = optional(object({
      compliance_regime         = string
      display_name              = string
      location                  = string
      organization              = string
      enable_sovereign_controls = bool
    }))
  }))
}