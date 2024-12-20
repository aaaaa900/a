# locals {
#   _custom_roles = {
#     for f in try(fileset(var.factories_config.custom_roles, "*.yaml"), []) :
#     replace(f, ".yaml", "") => yamldecode(
#       file("${var.factories_config.custom_roles}/${f}")
#     )
#   }
#   _iam_principal_roles = distinct(flatten(values(var.iam_by_principals)))
#   _iam_principals = {
#     for r in local._iam_principal_roles : r => [
#       for k, v in var.iam_by_principals :
#       k if try(index(v, r), null) != null
#     ]
#   }
#   custom_roles = merge(
#     {
#       for k, v in local._custom_roles : k => {
#         name        = lookup(v, "name", k)
#         permissions = v["includedPermissions"]
#       }
#     },
#     {
#       for k, v in var.custom_roles : k => {
#         name        = k
#         permissions = v
#       }
#     }
#   )
#   iam = {
#     for role in distinct(concat(keys(var.iam), keys(local._iam_principals))) :
#     role => concat(
#       try(var.iam[role], []),
#       try(local._iam_principals[role], [])
#     )
#   }
# }

# # we use a different key for custom roles to allow referring to the role alias
# # in Terraform, while still being able to define unique role names

# check "custom_roles" {
#   assert {
#     condition = (
#       length(local.custom_roles) == length({
#         for k, v in local.custom_roles : v.name => null
#       })
#     )
#     error_message = "Duplicate role name in custom roles."
#   }
# }

# resource "google_project_iam_custom_role" "roles" {
#   for_each    = local.custom_roles
#   project     = local.project.project_id
#   role_id     = each.value.name
#   title       = "Custom role ${each.value.name}"
#   description = "Terraform-managed."
#   permissions = each.value.permissions
# }

# resource "google_project_iam_binding" "authoritative" {
#   for_each = local.iam
#   project  = local.project.project_id
#   role     = each.key
#   members  = each.value
#   depends_on = [
#     google_project_service.project_services,
#     google_project_iam_custom_role.roles
#   ]
# }

# resource "google_project_iam_binding" "bindings" {
#   for_each = var.iam_bindings
#   project  = local.project.project_id
#   role     = each.value.role
#   members  = each.value.members
#   dynamic "condition" {
#     for_each = each.value.condition == null ? [] : [""]
#     content {
#       expression  = each.value.condition.expression
#       title       = each.value.condition.title
#       description = each.value.condition.description
#     }
#   }
#   depends_on = [
#     google_project_service.project_services,
#     google_project_iam_custom_role.roles
#   ]
# }

# resource "google_project_iam_member" "bindings" {
#   for_each = var.iam_bindings_additive
#   project  = local.project.project_id
#   role     = each.value.role
#   member   = each.value.member
#   dynamic "condition" {
#     for_each = each.value.condition == null ? [] : [""]
#     content {
#       expression  = each.value.condition.expression
#       title       = each.value.condition.title
#       description = each.value.condition.description
#     }
#   }
#   depends_on = [
#     google_project_service.project_services,
#     google_project_iam_custom_role.roles
#   ]
# }
