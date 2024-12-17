variable "folders" {
  description = "List of folders"
  type = list(object({
    name   = string
    parent = string
    # assured_workload_config = optional(object({
    #   compliance_regime         = string
    #   display_name              = string
    #   location                  = string
    #   organization              = string
    #   enable_sovereign_controls = bool
    # }))
    # subfolders = optional(list(object({})))
  }))

# validation {
#   condition = alltrue([
#     for folder in var.folders : 
#       length(folder.name) > 0 && length(folder.parent) > 0 &&
#       alltrue([
#         for subfolder in coalesce(folder.subfolders, []) : length(subfolder=)
#           (length(subfolder.name) > 0 && length(subfolder.parent) > 0)
#       ])
#   ])
#   error_message = "Chaque sous-dossier doit avoir des attributs 'name' et 'parent' non vides lorsqu'ils sont présents."
# }

}