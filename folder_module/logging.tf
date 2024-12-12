resource "google_logging_folder_settings" "default" {
  count                = var.logging_settings != null ? 1 : 0
  folder               = local.folder_id
  disable_default_sink = false # var.logging_settings.disable_default_sink => 0 log centralization for the moment
  storage_location     = var.logging_settings.storage_location
}

resource "google_folder_iam_audit_config" "default" {
  for_each = var.logging_data_access
  folder   = local.folder_id
  service  = each.key
  dynamic "audit_log_config" {
    for_each = each.value
    iterator = config
    content {
      log_type         = config.key
      exempted_members = config.value
    }
  }
}