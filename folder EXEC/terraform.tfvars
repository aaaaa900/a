folders = [
  {
    name   = "Folder1"
    parent = "organizations/123456789" # Organisation racine
  },
  {
    name   = "Folder2"
    parent = "Folder1" # Sous-dossier de Folder1
  },
  {
    name   = "Subfolder1"
    parent = "Folder2" # Sous-dossier de Folder2
  },
  {
    name   = "Folder3"
    parent = "organizations/123456789" # Un autre dossier racine
  },
  {
    name   = "Subfolder2"
    parent = "Folder3" # Sous-dossier de Folder3
  },
  {
    name   = "SubfolderSubFolder1"
    parent = "Subfolder2" # Sous-dossier de Folder3
  }
]




# folders = [
#   {
#     name     = "Folder1"
#     parent   = "organizations/0"
#     # iam_by_principals = {
#     #   "group:aa" = [
#     #     "roles/resourcemanager.projectCreator"
#     #   ]
#     # }
#     # iam = {
#     #   "roles/owner" = ["serviceAccount:aa"]
#     # }
#     # iam_bindings_additive = {
#     #   am1_storage_admin = {
#     #     member = "serviceAccount:aa"
#     #     role   = "roles/storage.admin"
#     #   }
#     # }
#     # assured_workload_config = {
#     #   compliance_regime         = "EU_REGIONS_AND_SUPPORT"
#     #   display_name              = "workload-name"
#     #   location                  = "europe-west1"
#     #   organization              = "organizations/0"
#     #   enable_sovereign_controls = true
#     # }
#     # logging_data_access = {
#     #   allServices = {
#     #     ADMIN_READ = ["group:aa"]
#     #   }
#     #   "storage.googleapis.com" = {
#     #     DATA_READ  = []
#     #     DATA_WRITE = []
#     #   }
#     # }
#     # folder_create = true
#     # id            = 12
#   },
#   {
#     name   = "Folder2"
#     parent = "folders/1111111111"
#     # folder_create = false
#     # id            = 12
#     subfolders = [
#           {
#             name = "Subsubfolder1",
#             parent   = "organizations/2"
#           }
#         ]
#   }
# ]
