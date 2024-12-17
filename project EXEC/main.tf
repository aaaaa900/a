provider "google" {
}

provider "google-beta" {
}

# module "project" {
#   source          = "../project_module"
#   billing_account = "01743A-7C5D33-B02596"
#   name            = "project"
#   # parent          = var.folder_id
#   prefix          = "aa"#var.prefix
#   # services = [
#   #   "container.googleapis.com",
#   #   "stackdriver.googleapis.com"
#   # ]
# }

# module "lb_external" {
#   source                         = "PaloAltoNetworks/swfw-modules/google//modules/lb_external"
#   version                        = "~> 2.0"
#   name                           = "vmseries-external-lb"
#   health_check_http_port         = 80
#   health_check_http_request_path = "/"

#   rules = {
#     "rule1" = { all_ports = true }
#   }
# }

module "service-project" {
  source          = "../project_module"
  billing_account = "01743A-7C5D33-B02596"
  name            = "service"
  # parent          = var.folder_id
  prefix          = "aa" #var.prefix
  org_policies = {
    "compute.restrictSharedVpcSubnetworks" = {
      rules = [{
        allow = {
          values = ["projects/host/regions/europe-west1/subnetworks/prod-default-ew1"]
        }
      }]
    }
  }
  services = [
    "container.googleapis.com",
  ]
  # shared_vpc_service_config = {
  #   enabled = true
  #   # host_project  = module.host-project.project_id
  #   # network_users = ["group:${var.group_email}"]
  #   # # reuse the list of services from the module's outputs
  #   # service_iam_grants = module.service-project.services
  # }

  #  shared_vpc_host_config = {
    # enabled = true
  # }
  #   logging_data_access = {
  #   allServices = {
  #     # logs for principals listed here will be excluded
  #     ADMIN_READ = ["group:aa"]
  #   }
  #   "storage.googleapis.com" = {
  #     DATA_READ  = []
  #     DATA_WRITE = []
  #   }
  # }
}
