output "assured_workload" {
  description = "Assured Workloads workload resource."
  value       = try(google_assured_workloads_workload.folder[0], null)
}

output "folder" {
  description = "Folder resource."
  value       = try(google_folder.folder[0], null)
}

output "id" {
  description = "Fully qualified folder id."
  value       = local.folder_id
  depends_on = [
    google_folder_iam_binding.authoritative,
    google_folder_iam_binding.bindings,
    google_folder_iam_member.bindings,
  ]
}

output "name" {
  description = "Folder name."
  value = (
    var.assured_workload_config == null
    ? try(google_folder.folder[0].display_name, null)
    : try(google_assured_workloads_workload.folder[0].resource_settings[0].display_name, null)
  )
}
