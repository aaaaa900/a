locals {
  folder_id = (
    var.assured_workload_config == null
    ? (
      var.folder_create
      ? try(google_folder.folder[0].id, null)
      : var.id
    )
    : format("folders/%s", try(google_assured_workloads_workload.folder[0].resources[0].resource_id, ""))
  )
  aw_parent = (
    # Assured Workload only accepls folder as a parent and uses organization as a parent when no value provided.
    var.parent == null
    ? null
    : (
      try(startswith(var.parent, "folders/"))
      ? var.parent
      : null
    )
  )
}

resource "google_folder" "folder" {
  count               = var.folder_create && var.assured_workload_config == null ? 1 : 0
  display_name        = var.name
  parent              = var.parent
  deletion_protection = var.deletion_protection
}

resource "google_assured_workloads_workload" "folder" {
  count                     = (var.assured_workload_config != null && var.folder_create) ? 1 : 0
  compliance_regime         = var.assured_workload_config.compliance_regime
  display_name              = var.assured_workload_config.display_name
  location                  = var.assured_workload_config.location
  organization              = var.assured_workload_config.organization
  enable_sovereign_controls = var.assured_workload_config.enable_sovereign_controls
  labels                    = var.assured_workload_config.labels
  partner                   = var.assured_workload_config.partner
  dynamic "partner_permissions" {
    for_each = try(var.assured_workload_config.partner_permissions, null) == null ? [] : [""]
    content {
      assured_workloads_monitoring = var.assured_workload_config.partner_permissions.assured_workloads_monitoring
      data_logs_viewer             = var.assured_workload_config.partner_permissions.data_logs_viewer
      service_access_approver      = var.assured_workload_config.partner_permissions.service_access_approver
    }
  }

  provisioned_resources_parent = local.aw_parent

  resource_settings {
    display_name  = var.name
    resource_type = "CONSUMER_FOLDER"
  }
  violation_notifications_enabled = var.assured_workload_config.violation_notifications_enabled
}
