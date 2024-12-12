provider "google" {
}

provider "google-beta" {
}

module "folder" {
  for_each = { for idx, folder in var.folders : idx => folder }
  source   = "./folder_module"

  name                  = each.value.name
  parent                = each.value.parent
  iam_by_principals     = lookup(each.value, "iam_by_principals", null)
  iam                   = lookup(each.value, "iam", null)
  iam_bindings_additive = lookup(each.value, "iam_bindings_additive", null)
  assured_workload_config = lookup(each.value, "assured_workload_config", null)
  logging_data_access   = lookup(each.value, "logging_data_access", null)
  folder_create         = lookup(each.value, "folder_create", true)
  id                    = lookup(each.value, "id", null)
}

# module "folder" {
#   for_each = { for idx, folder in var.folders : idx => folder }
#   source   = "./folder_module"
#   name     = each.value.name
#   parent   = each.value.parent

#   #   iam_by_principals = {
#   #     "group:aa" = [
#   #       "roles/owner",
#   #       "roles/resourcemanager.folderAdmin",
#   #       "roles/resourcemanager.projectCreator"
#   #     ]
#   #   }
#   #   iam = {
#   #     "roles/owner" = ["serviceAccount:aa"]
#   #   }
#   #   iam_bindings_additive = {
#   #     am1-storage-admin = {
#   #       member = "serviceAccount:aa"
#   #       role   = "roles/storage.admin"
#   #     }
#   #   }

#   #   assured_workload_config = {
#   #     compliance_regime         = "EU_REGIONS_AND_SUPPORT"
#   #     display_name              = "workload-name"
#   #     location                  = "europe-west1"
#   #     organization              = "organizations/0"
#   #     enable_sovereign_controls = true
#   #   }

#   #     logging_data_access = {
#   #         allServices = {
#   #         # logs for principals listed here will be excluded
#   #         ADMIN_READ = ["group:aa"]
#   #     }
#   #     "storage.googleapis.com" = {
#   #       DATA_READ  = []
#   #       DATA_WRITE = []
#   #     }
#   #   }

#   # folder_create to false requires to have specific ID, 
#   # If specified, it won"t recreate folder and only apply other resources
#   # For assured workload folders, when folder_create to false, no folder is created
#   #   id = "123" 
#   #   folder_create = false
# }