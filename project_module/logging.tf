# locals {
#   logging_sinks = {
#     for k, v in var.logging_sinks :
#     # rewrite destination and type when type="project"
#     k => merge(v, v.type != "project" ? {} : {
#       destination = "projects/${v.destination}"
#       type        = "logging"
#     })
#   }
#   sink_bindings = {
#     for type in ["bigquery", "logging", "project", "pubsub", "storage"] :
#     type => {
#       for name, sink in var.logging_sinks :
#       name => sink if sink.iam && sink.type == type
#     }
#   }
# }

# resource "google_project_iam_audit_config" "default" {
#   for_each = var.logging_data_access
#   project  = local.project.project_id
#   service  = each.key
#   dynamic "audit_log_config" {
#     for_each = each.value
#     iterator = config
#     content {
#       log_type         = config.key
#       exempted_members = config.value
#     }
#   }
# }

# resource "google_logging_project_sink" "sink" {
#   for_each               = local.logging_sinks
#   name                   = each.key
#   description            = coalesce(each.value.description, "${each.key} (Terraform-managed).")
#   project                = local.project.project_id
#   destination            = "${each.value.type}.googleapis.com/${each.value.destination}"
#   filter                 = each.value.filter
#   unique_writer_identity = each.value.unique_writer
#   disabled               = each.value.disabled

#   dynamic "bigquery_options" {
#     for_each = each.value.type == "bigquery" ? [""] : []
#     content {
#       use_partitioned_tables = each.value.bq_partitioned_table
#     }
#   }

#   dynamic "exclusions" {
#     for_each = each.value.exclusions
#     iterator = exclusion
#     content {
#       name   = exclusion.key
#       filter = exclusion.value
#     }
#   }

#   depends_on = [
#     google_project_iam_binding.authoritative,
#     google_project_iam_binding.bindings,
#     google_project_iam_member.bindings,
#     google_project_service.project_services
#   ]
# }

# resource "google_storage_bucket_iam_member" "gcs-sinks-binding" {
#   for_each = local.sink_bindings["storage"]
#   bucket   = each.value.destination
#   role     = "roles/storage.objectCreator"
#   member   = google_logging_project_sink.sink[each.key].writer_identity
# }

# resource "google_bigquery_dataset_iam_member" "bq-sinks-binding" {
#   for_each   = local.sink_bindings["bigquery"]
#   project    = split("/", each.value.destination)[1]
#   dataset_id = split("/", each.value.destination)[3]
#   role       = "roles/bigquery.dataEditor"
#   member     = google_logging_project_sink.sink[each.key].writer_identity
# }

# resource "google_pubsub_topic_iam_member" "pubsub-sinks-binding" {
#   for_each = local.sink_bindings["pubsub"]
#   project  = split("/", each.value.destination)[1]
#   topic    = split("/", each.value.destination)[3]
#   role     = "roles/pubsub.publisher"
#   member   = google_logging_project_sink.sink[each.key].writer_identity
# }

# resource "google_project_iam_member" "bucket-sinks-binding" {
#   for_each = local.sink_bindings["logging"]
#   project  = split("/", each.value.destination)[1]
#   role     = "roles/logging.bucketWriter"
#   member   = google_logging_project_sink.sink[each.key].writer_identity

#   condition {
#     title       = "${each.key} bucket writer"
#     description = "Grants bucketWriter to ${google_logging_project_sink.sink[each.key].writer_identity} used by log sink ${each.key} on ${local.project.project_id}"
#     expression  = "resource.name.endsWith('${each.value.destination}')"
#   }
# }

# resource "google_project_iam_member" "project-sinks-binding" {
#   for_each = local.sink_bindings["project"]
#   project  = each.value.destination
#   role     = "roles/logging.logWriter"
#   member   = google_logging_project_sink.sink[each.key].writer_identity
# }

# resource "google_logging_project_exclusion" "logging-exclusion" {
#   for_each    = var.logging_exclusions
#   name        = each.key
#   project     = local.project.project_id
#   description = "${each.key} (Terraform-managed)."
#   filter      = each.value
# }
