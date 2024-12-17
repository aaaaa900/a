# Project Module

This module implements the creation and management of one GCP project including IAM, organization policies, Shared VPC host or service attachment, service API activation, and tag attachment. It also offers a convenient way to refer to managed service identities (aka robot service accounts) for APIs.

## TOC

<!-- BEGIN TOC -->
- [TOC](#toc)
- [Basic Project Creation](#basic-project-creation)
- [IAM](#iam)
  - [Authoritative IAM](#authoritative-iam)
  - [Additive IAM](#additive-iam)
  - [Service Agents](#service-agents)
    - [Service Agent Aliases](#service-agent-aliases)
- [Shared VPC](#shared-vpc)
- [Organization Policies](#organization-policies)
  - [Organization Policy Factory](#organization-policy-factory)
  - [Dry-Run Mode](#dry-run-mode)
- [Log Sinks](#log-sinks)
- [Data Access Logs](#data-access-logs)
- [Cloud KMS Encryption Keys](#cloud-kms-encryption-keys)
- [Tags](#tags)
- [Tag Bindings](#tag-bindings)
- [Project-scoped Tags](#project-scoped-tags)
- [Custom Roles](#custom-roles)
  - [Custom Roles Factory](#custom-roles-factory)
- [Quotas](#quotas)
- [Quotas factory](#quotas-factory)
- [VPC Service Controls](#vpc-service-controls)
- [Project Related Outputs](#project-related-outputs)
  - [Managing project related configuration without creating it](#managing-project-related-configuration-without-creating-it)
- [Files](#files)
- [Variables](#variables)
- [Outputs](#outputs)
<!-- END TOC -->

## Basic Project Creation

```hcl
module "project" {
  source          = "./fabric/modules/project"
  billing_account = var.billing_account_id
  name            = "project"
  parent          = var.folder_id
  prefix          = var.prefix
  services = [
    "container.googleapis.com",
    "stackdriver.googleapis.com"
  ]
}
# tftest modules=1 resources=6 inventory=basic.yaml e2e
```

## IAM

IAM is managed via several variables that implement different features and levels of control:

- `iam` and `iam_by_principals` configure authoritative bindings that manage individual roles exclusively, and are internally merged
- `iam_bindings` configure authoritative bindings with optional support for conditions, and are not internally merged with the previous two variables
- `iam_bindings_additive` configure additive bindings via individual role/member pairs with optional support  conditions

The authoritative and additive approaches can be used together, provided different roles are managed by each. Some care must also be taken with the `iam_by_principals` variable to ensure that variable keys are static values, so that Terraform is able to compute the dependency graph.

Be mindful about service identity roles when using authoritative IAM, as you might inadvertently remove a role from a [service identity](https://cloud.google.com/iam/docs/service-account-types#google-managed) or default service account. For example, using `roles/editor` with `iam` or `iam_principals` will remove the default permissions for the Cloud Services identity. A simple workaround for these scenarios is described below.

### Authoritative IAM

The `iam` variable is based on role keys and is typically used for service accounts, or where member values can be dynamic and would create potential problems in the underlying `for_each` cycle.

```hcl
locals {
  gke_service_account = "my_gke_service_account"
}

module "project" {
  source          = "./fabric/modules/project"
  billing_account = var.billing_account_id
  name            = "project"
  parent          = var.folder_id
  prefix          = var.prefix
  services = [
    "container.googleapis.com",
    "stackdriver.googleapis.com"
  ]
  iam = {
    "roles/container.hostServiceAgentUser" = [
      "serviceAccount:${local.gke_service_account}"
    ]
  }
}
# tftest modules=1 resources=7 inventory=iam-authoritative.yaml
```

The `iam_by_principals` variable uses [principals](https://cloud.google.com/iam/docs/principal-identifiers) as keys and is a convenient way to assign roles to humans following Google's best practices. The end result is readable code that also serves as documentation.

```hcl
module "project" {
  source          = "./fabric/modules/project"
  billing_account = var.billing_account_id
  name            = "project"
  parent          = var.folder_id
  prefix          = var.prefix
  iam_by_principals = {
    "group:${var.group_email}" = [
      "roles/cloudasset.owner",
      "roles/cloudsupport.techSupportEditor",
      "roles/iam.securityReviewer",
      "roles/logging.admin",
    ]
  }
}
# tftest modules=1 resources=5 inventory=iam-group.yaml e2e
```

The `iam_bindings` variable behaves like a more verbose version of `iam`, and allows setting binding-level IAM conditions.

```hcl
module "project" {
  source          = "./fabric/modules/project"
  billing_account = var.billing_account_id
  name            = "project"
  parent          = var.folder_id
  prefix          = var.prefix
  services = [
    "stackdriver.googleapis.com"
  ]
  iam_bindings = {
    iam_admin_conditional = {
      members = [
        "group:${var.group_email}"
      ]
      role = "roles/resourcemanager.projectIamAdmin"
      condition = {
        title      = "delegated_network_user_one"
        expression = <<-END
          api.getAttribute(
            'iam.googleapis.com/modifiedGrantsByRole', []
          ).hasOnly([
            'roles/compute.networkAdmin'
          ])
        END
      }
    }
  }
}
# tftest modules=1 resources=3 inventory=iam-bindings.yaml e2e
```

### Additive IAM

Additive IAM is typically used where bindings for specific roles are controlled by different modules or in different Terraform stages. One common example is a host project managed by the networking team, and a project factory that manages service projects and needs to assign `roles/networkUser` on the host project.

The `iam_bindings_additive` variable allows setting individual role/principal binding pairs. Support for IAM conditions is implemented like for `iam_bindings` above.

```hcl
module "project" {
  source          = "./fabric/modules/project"
  billing_account = var.billing_account_id
  name            = "project"
  parent          = var.folder_id
  prefix          = var.prefix
  services = [
    "compute.googleapis.com"
  ]
  iam_bindings_additive = {
    group-owner = {
      member = "group:${var.group_email}"
      role   = "roles/owner"
    }
  }
}
# tftest modules=1 resources=4 inventory=iam-bindings-additive.yaml e2e
```

### Service Agents

By default, upon service activation, this module will perform the following actions:

- **Create primary service agents:** For each service listed in the `var.services` variable, the module will trigger the creation of the corresponding primary service agent (if any).
- **Grant agent-specific roles:** If a service agent has a predefined role associated with it, that role will be granted on project if its API matches any of the services in `var.services`.

You can control these actions by adjusting the settings in the `var.service_agents_config` variable. To prevent the creation of specific service agents or the assignment of their default roles, modify the relevant fields within this variable.

The `service_agents` output provides a convenient way to access information about all active service agents in the project. Note that this output only includes details for service agents that are currently active (i.e. their API is listed in `var.services`) within your project.

> [!IMPORTANT]
> You can only access a service agent's details through the `service_agents` output if its corresponding API is enabled through the `services` variable.

The complete list of Google Cloud service agents, including their names, default roles, and associated APIs, is maintained in the  [service-agents.yaml](./service-agents.yaml) file.  This file is regularly updated to reflect the [official list of Google Cloud service agents](https://cloud.google.com/iam/docs/service-agents) using the [`build_service_agents`](../../tools/build_service_agents.py) script.

#### Service Agent Aliases

Consider the code below:

```hcl
module "project" {
  source          = "./fabric/modules/project"
  billing_account = var.billing_account_id
  name            = "project"
  parent          = var.folder_id
  prefix          = var.prefix
  services = [
    "artifactregistry.googleapis.com",
    "container.googleapis.com",
  ]
}

# tftest modules=1 resources=8 e2e
```

The `service_agents` output for this snippet would look similar to this:

```tfvars
service_agents = {
  "artifactregistry" = {
    "api" = "artifactregistry.googleapis.com"
    "display_name" = "Artifact Registry Service Agent"
    "email" = "service-0123456789@gcp-sa-artifactregistry.iam.gserviceaccount.com"
    "iam_email" = "serviceAccount:service-0123456789@gcp-sa-artifactregistry.iam.gserviceaccount.com"
    "is_primary" = true
    "role" = "roles/artifactregistry.serviceAgent"
  }
  "cloudservices" = {
    "api" = null
    "display_name" = "Google APIs Service Agent"
    "email" = "0123456789@cloudservices.gserviceaccount.com"
    "iam_email" = "serviceAccount:0123456789@cloudservices.gserviceaccount.com"
    "is_primary" = false
    "role" = null
  }
  "cloudsvc" = {
    "api" = null
    "display_name" = "Google APIs Service Agent"
    "email" = "0123456789@cloudservices.gserviceaccount.com"
    "iam_email" = "serviceAccount:0123456789@cloudservices.gserviceaccount.com"
    "is_primary" = false
    "role" = null
  }
  "container" = {
    "api" = "container.googleapis.com"
    "display_name" = "Kubernetes Engine Service Agent"
    "email" = "service-0123456789@container-engine-robot.iam.gserviceaccount.com"
    "iam_email" = "serviceAccount:service-0123456789@container-engine-robot.iam.gserviceaccount.com"
    "is_primary" = true
    "role" = "roles/container.serviceAgent"
  }
  "container-engine" = {
    "api" = "container.googleapis.com"
    "display_name" = "Kubernetes Engine Service Agent"
    "email" = "service-0123456789@container-engine-robot.iam.gserviceaccount.com"
    "iam_email" = "serviceAccount:service-0123456789@container-engine-robot.iam.gserviceaccount.com"
    "is_primary" = true
    "role" = "roles/container.serviceAgent"
  }
  "container-engine-robot" = {
    "api" = "container.googleapis.com"
    "display_name" = "Kubernetes Engine Service Agent"
    "email" = "service-0123456789@container-engine-robot.iam.gserviceaccount.com"
    "iam_email" = "serviceAccount:service-0123456789@container-engine-robot.iam.gserviceaccount.com"
    "is_primary" = true
    "role" = "roles/container.serviceAgent"
  }
  "gkenode" = {
    "api" = "container.googleapis.com"
    "display_name" = "Kubernetes Engine Node Service Agent"
    "email" = "service-0123456789@gcp-sa-gkenode.iam.gserviceaccount.com"
    "iam_email" = "serviceAccount:service-0123456789@gcp-sa-gkenode.iam.gserviceaccount.com"
    "is_primary" = false
    "role" = "roles/container.nodeServiceAgent"
  }
}
```

Notice that some service agents appear under multiple names. For example, the Kubernetes Engine Service Agent shows up as `container-engine-robot` but also has the `container` and `container-engine` aliases. These aliases exist only in Fabric for convenience and backwards compatibility. Refer to the table below for the list of aliases.

| Canonical Name                 | Aliases                    |
|--------------------------------|----------------------------|
| bigquery-encryption            | bq                         |
| cloudservices                  | cloudsvc                   |
| compute-system                 | compute                    |
| cloudcomposer-accounts         | composer                   |
| container-engine-robot         | container container-engine |
| dataflow-service-producer-prod | dataflow                   |
| dataproc-accounts              | dataproc                   |
| gae-api-prod                   | gae-flex                   |
| gcf-admin-robot                | cloudfunctions gcf         |
| gkehub                         | fleet                      |
| gs-project-accounts            | storage                    |
| monitoring-notification        | monitoring                 |
| serverless-robot-prod          | cloudrun run               |

## Shared VPC

The module allows managing Shared VPC status for both hosts and service projects, and control of IAM bindings for service agents.

Project service association for VPC host projects can be

- authoritatively managed in the host project by enabling Shared VPC and specifying the set of service projects, or
- additively managed in service projects by enabling Shared VPC in the host project and then "attaching" each service project independently

IAM bindings in the host project for API service identities can be managed from service projects in two different ways:

- via the `service_agent_iam` attribute, by specifying the set of roles and service agents
- via the `service_iam_grants` attribute that leverages a [fixed list of roles for each service](./sharedvpc-agent-iam.yaml), by specifying a list of services
- via the `service_agent_subnet_iam` attribute, by providing a map of `"<region>/<subnet_name>"` -> `[ "<service_identity>", (...)]`, to grant `compute.networkUser` role on subnet level to service identity

While the first method is more explicit and readable, the second method is simpler and less error prone as all appropriate roles are predefined for all required service agents (e.g. compute and cloud services). You can mix and match as the two sets of bindings are then internally combined.

This example shows a simple configuration with a host project, and a service project independently attached with granular IAM bindings for service identities. The full list of service agent names can be found in [service-agents.yaml](./service-agents.yaml)

```hcl
module "host-project" {
  source          = "./fabric/modules/project"
  billing_account = var.billing_account_id
  name            = "host"
  parent          = var.folder_id
  prefix          = var.prefix
  shared_vpc_host_config = {
    enabled = true
  }
}

module "service-project" {
  source          = "./fabric/modules/project"
  billing_account = var.billing_account_id
  name            = "service"
  parent          = var.folder_id
  prefix          = var.prefix
  services = [
    "container.googleapis.com",
    "run.googleapis.com"
  ]
  shared_vpc_service_config = {
    host_project = module.host-project.project_id
    service_agent_iam = {
      "roles/compute.networkUser" = [
        "cloudservices", "container-engine"
      ]
      "roles/vpcaccess.user" = [
        "cloudrun"
      ]
      "roles/container.hostServiceAgentUser" = [
        "container-engine"
      ]
    }
  }
}
# tftest modules=2 resources=15 inventory=shared-vpc.yaml e2e
```

This example shows a similar configuration, with the simpler way of defining IAM bindings for service identities. The list of services passed to `service_iam_grants` uses the same module's outputs to establish a dependency, as service agents are typically only available after service (API) activation.

```hcl
module "host-project" {
  source          = "./fabric/modules/project"
  billing_account = var.billing_account_id
  name            = "host"
  parent          = var.folder_id
  prefix          = var.prefix
  shared_vpc_host_config = {
    enabled = true
  }
}

module "service-project" {
  source          = "./fabric/modules/project"
  billing_account = var.billing_account_id
  name            = "service"
  parent          = var.folder_id
  prefix          = var.prefix
  services = [
    "container.googleapis.com",
  ]
  shared_vpc_service_config = {
    host_project = module.host-project.project_id
    # reuse the list of services from the module's outputs
    service_iam_grants = module.service-project.services
  }
}
# tftest modules=2 resources=12 inventory=shared-vpc-auto-grants.yaml e2e
```

The `compute.networkUser` role for identities other than API services (e.g. users, groups or service accounts) can be managed via the `network_users` attribute, by specifying the list of identities. Avoid using dynamically generated lists, as this attribute is involved in a `for_each` loop and may result in Terraform errors.

Note that this configuration grants the role at project level which results in the identities being able to configure resources on all the VPCs and subnets belonging to the host project. The most reliable way to restrict which subnets can be used on the newly created project is via the `compute.restrictSharedVpcSubnetworks` organization policy. For more information on the Org Policy configuration check the corresponding [Organization Policy section](#organization-policies). The following example details this configuration.

```hcl
module "host-project" {
  source          = "./fabric/modules/project"
  billing_account = var.billing_account_id
  name            = "host"
  parent          = var.folder_id
  prefix          = var.prefix
  shared_vpc_host_config = {
    enabled = true
  }
}

module "service-project" {
  source          = "./fabric/modules/project"
  billing_account = var.billing_account_id
  name            = "service"
  parent          = var.folder_id
  prefix          = var.prefix
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
  shared_vpc_service_config = {
    host_project  = module.host-project.project_id
    network_users = ["group:${var.group_email}"]
    # reuse the list of services from the module's outputs
    service_iam_grants = module.service-project.services
  }
}
# tftest modules=2 resources=14 inventory=shared-vpc-host-project-iam.yaml e2e
```

In specific cases it might make sense to selectively grant the `compute.networkUser` role for service identities at the subnet level, and while that is best done via org policies it's also supported by this module. In this example, Compute service identity and `team-1@example.com` Google Group will be granted compute.networkUser in the `gce` subnet defined in `europe-west1` region in the `host` project (not included in the example) via the `service_agent_subnet_iam` and `network_subnet_users` attributes.

```hcl
module "host-project" {
  source          = "./fabric/modules/project"
  billing_account = var.billing_account_id
  name            = "host"
  parent          = var.folder_id
  prefix          = var.prefix
  shared_vpc_host_config = {
    enabled = true
  }
}

module "service-project" {
  source          = "./fabric/modules/project"
  billing_account = var.billing_account_id
  name            = "service"
  parent          = var.folder_id
  prefix          = var.prefix
  services = [
    "compute.googleapis.com",
  ]
  shared_vpc_service_config = {
    host_project = module.host-project.project_id
    service_agent_subnet_iam = {
      "europe-west1/gce" = ["compute"]
    }
    network_subnet_users = {
      "europe-west1/gce" = ["group:team-1@example.com"]
    }
  }
}
# tftest modules=2 resources=8 inventory=shared-vpc-subnet-grants.yaml
```

## Organization Policies

To manage organization policies, the `orgpolicy.googleapis.com` service should be enabled in the quota project.

```hcl
module "project" {
  source          = "./fabric/modules/project"
  billing_account = var.billing_account_id
  name            = "project"
  parent          = var.folder_id
  prefix          = var.prefix
  org_policies = {
    "compute.disableGuestAttributesAccess" = {
      rules = [{ enforce = true }]
    }
    "compute.skipDefaultNetworkCreation" = {
      rules = [{ enforce = true }]
    }
    "iam.disableServiceAccountKeyCreation" = {
      rules = [{ enforce = true }]
    }
    "iam.disableServiceAccountKeyUpload" = {
      rules = [
        {
          condition = {
            expression  = "resource.matchTagId('tagKeys/1234', 'tagValues/1234')"
            title       = "condition"
            description = "test condition"
            location    = "somewhere"
          }
          enforce = true
        },
        {
          enforce = false
        }
      ]
    }
    "iam.allowedPolicyMemberDomains" = {
      rules = [{
        allow = {
          values = ["C0xxxxxxx", "C0yyyyyyy"]
        }
      }]
    }
    "compute.trustedImageProjects" = {
      rules = [{
        allow = {
          values = ["projects/my-project"]
        }
      }]
    }
    "compute.vmExternalIpAccess" = {
      rules = [{ deny = { all = true } }]
    }
  }
}
# tftest modules=1 resources=8 inventory=org-policies.yaml e2e
```

### Organization Policy Factory

Organization policies can be loaded from a directory containing YAML files where each file defines one or more constraints. The structure of the YAML files is exactly the same as the `org_policies` variable.

Note that constraints defined via `org_policies` take precedence over those in `org_policies_data_path`. In other words, if you specify the same constraint in a YAML file *and* in the `org_policies` variable, the latter will take priority.

The example below deploys a few organization policies split between two YAML files.

```hcl
module "project" {
  source          = "./fabric/modules/project"
  billing_account = var.billing_account_id
  name            = "project"
  parent          = var.folder_id
  prefix          = var.prefix
  factories_config = {
    org_policies = "configs/org-policies/"
  }
}
# tftest modules=1 resources=8 files=boolean,list inventory=org-policies.yaml e2e
```

```yaml
compute.disableGuestAttributesAccess:
  rules:
  - enforce: true
compute.skipDefaultNetworkCreation:
  rules:
  - enforce: true
iam.disableServiceAccountKeyCreation:
  rules:
  - enforce: true
iam.disableServiceAccountKeyUpload:
  rules:
  - condition:
      description: test condition
      expression: resource.matchTagId('tagKeys/1234', 'tagValues/1234')
      location: somewhere
      title: condition
    enforce: true
  - enforce: false

# tftest-file id=boolean path=configs/org-policies/boolean.yaml schema=org-policies.schema.json
```

```yaml
compute.trustedImageProjects:
  rules:
  - allow:
      values:
      - projects/my-project
compute.vmExternalIpAccess:
  rules:
  - deny:
      all: true
iam.allowedPolicyMemberDomains:
  rules:
  - allow:
      values:
      - C0xxxxxxx
      - C0yyyyyyy

# tftest-file id=list path=configs/org-policies/list.yaml schema=org-policies.schema.json
```

### Dry-Run Mode

To enable dry-run mode, add the `dry_run:` prefix to the constraint name in your Terraform configuration:

```hcl
module "project" {
  source = "./fabric/modules/project"
  name   = "project"
  parent = var.folder_id
  org_policies = {
    "gcp.restrictTLSVersion" = {
      rules = [{ deny = { values = ["TLS_VERSION_1"] } }]
    }
    "dry_run:gcp.restrictTLSVersion" = {
      rules = [{ deny = { values = ["TLS_VERSION_1", "TLS_VERSION_1_1"] } }]
    }
  }
}
# tftest modules=1 resources=2 inventory=org-policies-dry-run.yaml
```

## Log Sinks

```hcl
module "gcs" {
  source        = "./fabric/modules/gcs"
  project_id    = var.project_id
  name          = "gcs_sink"
  location      = "EU"
  prefix        = var.prefix
  force_destroy = true
}

module "dataset" {
  source     = "./fabric/modules/bigquery-dataset"
  project_id = var.project_id
  id         = "bq_sink"
  options    = { delete_contents_on_destroy = true }
}

module "pubsub" {
  source     = "./fabric/modules/pubsub"
  project_id = var.project_id
  name       = "pubsub_sink"
}

module "bucket" {
  source      = "./fabric/modules/logging-bucket"
  parent_type = "project"
  parent      = var.project_id
  id          = "${var.prefix}-bucket"
}

module "destination-project" {
  source          = "./fabric/modules/project"
  name            = "dest-prj"
  billing_account = var.billing_account_id
  parent          = var.folder_id
  prefix          = var.prefix
  services = [
    "logging.googleapis.com"
  ]
}

module "project-host" {
  source          = "./fabric/modules/project"
  name            = "project"
  billing_account = var.billing_account_id
  parent          = var.folder_id
  prefix          = var.prefix
  services = [
    "logging.googleapis.com"
  ]
  logging_sinks = {
    warnings = {
      destination = module.gcs.id
      filter      = "severity=WARNING"
      type        = "storage"
    }
    info = {
      destination = module.dataset.id
      filter      = "severity=INFO"
      type        = "bigquery"
    }
    notice = {
      destination = module.pubsub.id
      filter      = "severity=NOTICE"
      type        = "pubsub"
    }
    debug = {
      destination = module.bucket.id
      filter      = "severity=DEBUG"
      exclusions = {
        no-compute = "logName:compute"
      }
      type = "logging"
    }
    alert = {
      destination = module.destination-project.id
      filter      = "severity=ALERT"
      type        = "project"
    }
  }
  logging_exclusions = {
    no-gce-instances = "resource.type=gce_instance"
  }
}
# tftest modules=6 resources=19 inventory=logging.yaml e2e
```

## Data Access Logs

Activation of data access logs can be controlled via the `logging_data_access` variable. If the `iam_bindings_authoritative` variable is used to set a resource-level IAM policy, the data access log configuration will also be authoritative as part of the policy.

This example shows how to set a non-authoritative access log configuration:

```hcl
module "project" {
  source          = "./fabric/modules/project"
  name            = "project"
  billing_account = var.billing_account_id
  parent          = var.folder_id
  prefix          = var.prefix
  logging_data_access = {
    allServices = {
      # logs for principals listed here will be excluded
      ADMIN_READ = ["group:${var.group_email}"]
    }
    "storage.googleapis.com" = {
      DATA_READ  = []
      DATA_WRITE = []
    }
  }
}
# tftest modules=1 resources=3 inventory=logging-data-access.yaml e2e
```

## Cloud KMS Encryption Keys

This module streamlines the process of granting KMS encryption/decryption permissions. By assigning the `roles/cloudkms.cryptoKeyEncrypterDecrypter` role, it ensures that all required service agents for a service (such as Cloud Composer, which depends on multiple agents) have the necessary access to the keys.

```hcl
module "project" {
  source          = "./fabric/modules/project"
  billing_account = var.billing_account_id
  name            = "project"
  prefix          = var.prefix
  parent          = var.folder_id
  services = [
    "compute.googleapis.com",
    "storage.googleapis.com"
  ]
  service_encryption_key_ids = {
    "compute.googleapis.com" = [module.kms.keys.key-regional.id]
    "storage.googleapis.com" = [module.kms.keys.key-regional.id]
  }
}

module "kms" {
  source     = "./fabric/modules/kms"
  project_id = var.project_id # KMS is in different project to prevent dependency cycle
  keyring = {
    location = var.region
    name     = "keyring"
  }
  keys = {
    "key-regional" = {
    }
  }
  iam = {
    "roles/cloudkms.cryptoKeyEncrypterDecrypter" = [
      module.project.service_agents.compute.iam_email,
      module.project.service_agents.storage.iam_email,
    ]
  }
}

# tftest modules=2 resources=10 e2e
```

## Tags

Refer to the [Creating and managing tags](https://cloud.google.com/resource-manager/docs/tags/tags-creating-and-managing) documentation for details on usage.

```hcl
module "project" {
  source          = "./fabric/modules/project"
  billing_account = var.billing_account_id
  name            = "project"
  prefix          = var.prefix
  parent          = var.folder_id
  services = [
    "compute.googleapis.com",
  ]
  tags = {
    environment = {
      description = "Environment specification."
      iam = {
        "roles/resourcemanager.tagAdmin" = ["group:${var.group_email}"]
      }
      iam_bindings = {
        viewer = {
          role    = "roles/resourcemanager.tagViewer"
          members = ["group:gcp-support@example.org"]
        }
      }
      iam_bindings_additive = {
        user_app1 = {
          role   = "roles/resourcemanager.tagUser"
          member = "group:app1-team@example.org"
        }
      }
      values = {
        dev = {
          iam_bindings_additive = {
            user_app2 = {
              role   = "roles/resourcemanager.tagUser"
              member = "group:app2-team@example.org"
            }
          }
        }
        prod = {
          description = "Environment: production."
          iam = {
            "roles/resourcemanager.tagViewer" = ["group:app1-team@example.org"]
          }
          iam_bindings = {
            admin = {
              role    = "roles/resourcemanager.tagAdmin"
              members = ["group:gcp-support@example.org"]
              condition = {
                title      = "gcp_support"
                expression = <<-END
                  request.time.getHours("Europe/Berlin") <= 9 &&
                  request.time.getHours("Europe/Berlin") >= 17
                END
              }
            }
          }
        }
      }
    }
  }
  tag_bindings = {
    env-prod = module.project.tag_values["environment/prod"].id
  }
}
# tftest modules=1 resources=13 inventory=tags.yaml
```

You can also define network tags through the dedicated `network_tags` variable:

```hcl
module "project" {
  source          = "./fabric/modules/project"
  billing_account = var.billing_account_id
  name            = "project"
  prefix          = var.prefix
  parent          = var.folder_id
  services = [
    "compute.googleapis.com"
  ]
  network_tags = {
    net-environment = {
      description = "This is a network tag."
      network     = "${var.project_id}/${var.vpc.name}"
      iam = {
        "roles/resourcemanager.tagAdmin" = ["group:${var.group_email}"]
      }
      values = {
        dev = {}
        prod = {
          description = "Environment: production."
          iam = {
            "roles/resourcemanager.tagUser" = ["group:${var.group_email}"]
          }
        }
      }
    }
  }
}
# tftest modules=1 resources=8 inventory=tags-network.yaml
```

## Tag Bindings

You can bind secure tags to a project with the `tag_bindings` attribute

```hcl
module "org" {
  source          = "./fabric/modules/organization"
  organization_id = var.organization_id
  tags = {
    environment = {
      description = "Environment specification."
      values = {
        dev  = {}
        prod = {}
      }
    }
  }
}

module "project" {
  source = "./fabric/modules/project"
  name   = "project"
  parent = var.folder_id
  tag_bindings = {
    env-prod = module.org.tag_values["environment/prod"].id
    foo      = "tagValues/12345678"
  }
}
# tftest modules=2 resources=6
```

## Project-scoped Tags

To create project-scoped secure tags, use the `tags` and `network_tags` attributes.

```hcl
module "project" {
  source = "./fabric/modules/project"
  name   = "project"
  parent = var.folder_id
  tags = {
    mytag1 = {}
    mytag2 = {
      iam = {
        "roles/resourcemanager.tagAdmin" = ["user:admin@example.com"]
      }
      values = {
        myvalue1 = {}
        myvalue2 = {
          iam = {
            "roles/resourcemanager.tagUser" = ["user:user@example.com"]
          }
        }
      }
    }
  }
  network_tags = {
    my_net_tag = {
      network = "${var.project_id}/${var.vpc.name}"
    }
  }
}
# tftest modules=1 resources=8
```

## Custom Roles

Custom roles can be defined via the `custom_roles` variable, and referenced via the `custom_role_id` output (this also provides explicit dependency on the custom role):

```hcl
module "project" {
  source = "./fabric/modules/project"
  name   = "project"
  custom_roles = {
    "myRole" = [
      "compute.instances.list",
    ]
  }
  iam = {
    (module.project.custom_role_id.myRole) = ["group:${var.group_email}"]
  }
}
# tftest modules=1 resources=3
```

### Custom Roles Factory

Custom roles can also be specified via a factory in a similar way to organization policies and policy constraints. Each file is mapped to a custom role, where

- the role name defaults to the file name but can be overridden via a `name` attribute in the yaml
- role permissions are defined in an `includedPermissions` map

Custom roles defined via the variable are merged with those coming from the factory, and override them in case of duplicate names.

```hcl
module "project" {
  source = "./fabric/modules/project"
  name   = "project"
  factories_config = {
    custom_roles = "data/custom_roles"
  }
}
# tftest modules=1 resources=3 files=custom-role-1,custom-role-2
```

```yaml
includedPermissions:
 - compute.globalOperations.get

# tftest-file id=custom-role-1 path=data/custom_roles/test_1.yaml schema=custom-role.schema.json
```

```yaml
name: projectViewer
includedPermissions:
  - resourcemanager.projects.get
  - resourcemanager.projects.getIamPolicy
  - resourcemanager.projects.list

# tftest-file id=custom-role-2 path=data/custom_roles/test_2.yaml schema=custom-role.schema.json
```

## Quotas

Project and regional quotas can be managed via the `quotas` variable. Keep in mind, that metrics returned by `gcloud compute regions describe` do not match `quota_id`s. To get a list of quotas in the project use the API call, for example to get quotas for `compute.googleapis.com` use:

```bash
curl -X GET \
  -H "Authorization: Bearer $(gcloud auth print-access-token)" \
  -H "X-Goog-User-Project: ${PROJECT_ID}" \
  "https://cloudquotas.googleapis.com/v1/projects/${PROJECT_ID}/locations/global/services/compute.googleapis.com/quotaInfos?pageSize=1000" \
  | grep quotaId
```

```hcl
module "project" {
  source          = "./fabric/modules/project"
  name            = "project"
  billing_account = var.billing_account_id
  parent          = var.folder_id
  prefix          = var.prefix
  quotas = {
    cpus-ew8 = {
      service         = "compute.googleapis.com"
      quota_id        = "CPUS-per-project-region"
      contact_email   = "user@example.com"
      preferred_value = 751
      dimensions = {
        region = "europe-west8"
      }
    }
  }
  services = [
    "cloudquotas.googleapis.com",
    "compute.googleapis.com"
  ]
}
# tftest modules=1 resources=5 inventory=quotas.yaml e2e
```

## Quotas factory

Quotas can be also specified via a factory in a similar way to organization policies, policy constraints and custom roles by pointing to a directory containing YAML files where each file defines one or more quotas. The structure of the YAML files is exactly the same as the `quotas` variable.

```hcl
module "project" {
  source          = "./fabric/modules/project"
  name            = "project"
  billing_account = var.billing_account_id
  parent          = var.folder_id
  prefix          = var.prefix
  factories_config = {
    quotas = "data/quotas"
  }
  services = [
    "cloudquotas.googleapis.com",
    "compute.googleapis.com"
  ]
}
# tftest modules=1 resources=5 files=quota-cpus-ew8 inventory=quotas.yaml e2e
```

```yaml
cpus-ew8:
  service: compute.googleapis.com
  quota_id: CPUS-per-project-region
  contact_email: user@example.com
  preferred_value: 751
  dimensions:
    region: europe-west8

# tftest-file id=quota-cpus-ew8 path=data/quotas/cpus-ew8.yaml schema=quotas.schema.json
```

## VPC Service Controls

This module also allows managing project membership in VPC Service Controls perimeters. When using this functionality care should be taken so that perimeter management (e.g. via the `vpc-sc` module) does not try reconciling resources, to avoid permadiffs and related violations.

```hcl
module "project" {
  source          = "./fabric/modules/project"
  billing_account = var.billing_account_id
  name            = "project"
  parent          = var.folder_id
  prefix          = var.prefix
  services = [
    "stackdriver.googleapis.com"
  ]
  vpc_sc = {
    perimeter_name = "accessPolicies/1234567890/servicePerimeters/default"
  }
}
# tftest modules=1 resources=3 inventory=vpc-sc.yaml
```

Perimeter bridges and dry run configuration are also supported.

```hcl
module "project" {
  source          = "./fabric/modules/project"
  billing_account = var.billing_account_id
  name            = "project"
  parent          = var.folder_id
  prefix          = var.prefix
  services = [
    "stackdriver.googleapis.com"
  ]
  vpc_sc = {
    perimeter_name = "accessPolicies/1234567890/servicePerimeters/default"
    perimeter_bridges = [
      "accessPolicies/1234567890/servicePerimeters/b1",
      "accessPolicies/1234567890/servicePerimeters/b2",
    ]
    is_dry_run = true
  }
}
# tftest modules=1 resources=5
```

## Project Related Outputs

Most of this module's outputs depend on its resources, to allow Terraform to compute all dependencies required for the project to be correctly configured. This allows you to reference outputs like `project_id` in other modules or resources without having to worry about setting `depends_on` blocks manually.

The `default_service_accounts` contains the emails of the default service accounts the project.

```hcl
module "project" {
  source          = "./fabric/modules/project"
  billing_account = var.billing_account_id
  name            = "project"
  prefix          = var.prefix
  parent          = var.folder_id
  services = [
    "compute.googleapis.com"
  ]
}

output "default_service_accounts" {
  value = module.project.default_service_accounts
}
# tftest modules=1 resources=3 inventory=outputs.yaml e2e
```

### Managing project related configuration without creating it

The module offers managing all related resources without ever touching the project itself by using `project_create = false`

```hcl
module "create-project" {
  source          = "./fabric/modules/project"
  billing_account = var.billing_account_id
  name            = "project"
  parent          = var.folder_id
  prefix          = var.prefix
}

module "project" {
  source          = "./fabric/modules/project"
  depends_on      = [module.create-project]
  billing_account = var.billing_account_id
  name            = "project"
  parent          = var.folder_id
  prefix          = var.prefix
  project_create  = false

  iam_by_principals = {
    "group:${var.group_email}" = [
      "roles/cloudasset.owner",
      "roles/cloudsupport.techSupportEditor",
      "roles/iam.securityReviewer",
      "roles/logging.admin",
    ]
  }
  iam_bindings = {
    iam_admin_conditional = {
      members = [
        "group:${var.group_email}"
      ]
      role = "roles/resourcemanager.projectIamAdmin"
      condition = {
        title      = "delegated_network_user_one"
        expression = <<-END
          api.getAttribute(
            'iam.googleapis.com/modifiedGrantsByRole', []
          ).hasOnly([
            'roles/compute.networkAdmin'
          ])
        END
      }
    }
  }
  iam_bindings_additive = {
    group-owner = {
      member = "group:${var.group_email}"
      role   = "roles/owner"
    }
  }
  iam = {
    "roles/editor" = [
      module.project.service_agents.cloudservices.iam_email
    ]
    "roles/apigee.serviceAgent" = [
      module.project.service_agents.apigee.iam_email
    ]
  }
  logging_data_access = {
    allServices = {
      # logs for principals listed here will be excluded
      ADMIN_READ = ["group:${var.group_email}"]
    }
    "storage.googleapis.com" = {
      DATA_READ  = []
      DATA_WRITE = []
    }
  }
  logging_sinks = {
    warnings = {
      destination = module.gcs.id
      filter      = "severity=WARNING"
      type        = "storage"
    }
    info = {
      destination = module.dataset.id
      filter      = "severity=INFO"
      type        = "bigquery"
    }
    notice = {
      destination = module.pubsub.id
      filter      = "severity=NOTICE"
      type        = "pubsub"
    }
    debug = {
      destination = module.bucket.id
      filter      = "severity=DEBUG"
      exclusions = {
        no-compute = "logName:compute"
      }
      type = "logging"
    }
  }
  logging_exclusions = {
    no-gce-instances = "resource.type=gce_instance"
  }
  org_policies = {
    "compute.disableGuestAttributesAccess" = {
      rules = [{ enforce = true }]
    }
    "compute.skipDefaultNetworkCreation" = {
      rules = [{ enforce = true }]
    }
    "iam.disableServiceAccountKeyCreation" = {
      rules = [{ enforce = true }]
    }
    "iam.disableServiceAccountKeyUpload" = {
      rules = [
        {
          condition = {
            expression  = "resource.matchTagId('tagKeys/1234', 'tagValues/1234')"
            title       = "condition"
            description = "test condition"
            location    = "somewhere"
          }
          enforce = true
        },
        {
          enforce = false
        }
      ]
    }
    "iam.allowedPolicyMemberDomains" = {
      rules = [{
        allow = {
          values = ["C0xxxxxxx", "C0yyyyyyy"]
        }
      }]
    }
    "compute.trustedImageProjects" = {
      rules = [{
        allow = {
          values = ["projects/my-project"]
        }
      }]
    }
    "compute.vmExternalIpAccess" = {
      rules = [{ deny = { all = true } }]
    }
  }
  shared_vpc_service_config = {
    host_project       = module.host-project.project_id
    service_iam_grants = module.project.services
    service_agent_iam = {
      "roles/cloudasset.owner" = [
        "cloudservices", "container-engine"
      ]
    }
  }
  services = [
    "apigee.googleapis.com",
    "bigquery.googleapis.com",
    "container.googleapis.com",
    "compute.googleapis.com",
    "logging.googleapis.com",
    "run.googleapis.com",
    "storage.googleapis.com",
  ]
  service_encryption_key_ids = {
    "compute.googleapis.com" = [module.kms.keys.key-global.id]
    "storage.googleapis.com" = [module.kms.keys.key-global.id]
  }
}

module "kms" {
  source     = "./fabric/modules/kms"
  project_id = var.project_id # Keys come from different project to prevent dependency cycle
  keyring = {
    location = "global"
    name     = "keyring"
  }
  keys = {
    "key-global" = {
    }
  }
  iam = {
    "roles/cloudkms.cryptoKeyEncrypterDecrypter" = [
      module.project.service_agents.compute.iam_email,
      module.project.service_agents.storage.iam_email
    ]
  }
}

module "host-project" {
  source          = "./fabric/modules/project"
  billing_account = var.billing_account_id
  name            = "host"
  parent          = var.folder_id
  prefix          = var.prefix
  shared_vpc_host_config = {
    enabled = true
  }
}

module "gcs" {
  source        = "./fabric/modules/gcs"
  project_id    = var.project_id
  name          = "gcs_sink"
  location      = "EU"
  prefix        = var.prefix
  force_destroy = true
}

module "dataset" {
  source     = "./fabric/modules/bigquery-dataset"
  project_id = var.project_id
  id         = "bq_sink"
  options    = { delete_contents_on_destroy = true }
}

module "pubsub" {
  source     = "./fabric/modules/pubsub"
  project_id = var.project_id
  name       = "pubsub_sink"
}

module "bucket" {
  source      = "./fabric/modules/logging-bucket"
  parent_type = "project"
  parent      = var.project_id
  id          = "${var.prefix}-bucket"
}
# tftest inventory=data.yaml e2e
```

<!-- TFDOC OPTS files:1 -->
<!-- BEGIN TFDOC -->
## Files

| name | description | resources |
|---|---|---|
| [cmek.tf](./cmek.tf) | Service Agent IAM Bindings for CMEK | <code>google_kms_crypto_key_iam_member</code> |
| [iam.tf](./iam.tf) | IAM bindings. | <code>google_project_iam_binding</code> · <code>google_project_iam_custom_role</code> · <code>google_project_iam_member</code> |
| [logging.tf](./logging.tf) | Log sinks and supporting resources. | <code>google_bigquery_dataset_iam_member</code> · <code>google_logging_project_exclusion</code> · <code>google_logging_project_sink</code> · <code>google_project_iam_audit_config</code> · <code>google_project_iam_member</code> · <code>google_pubsub_topic_iam_member</code> · <code>google_storage_bucket_iam_member</code> |
| [main.tf](./main.tf) | Module-level locals and resources. | <code>google_compute_project_metadata_item</code> · <code>google_essential_contacts_contact</code> · <code>google_monitoring_monitored_project</code> · <code>google_project</code> · <code>google_project_service</code> · <code>google_resource_manager_lien</code> |
| [organization-policies.tf](./organization-policies.tf) | Project-level organization policies. | <code>google_org_policy_policy</code> |
| [outputs.tf](./outputs.tf) | Module outputs. |  |
| [quotas.tf](./quotas.tf) | None | <code>google_cloud_quotas_quota_preference</code> |
| [service-agents.tf](./service-agents.tf) | Service agents supporting resources. | <code>google_project_default_service_accounts</code> · <code>google_project_iam_member</code> · <code>google_project_service_identity</code> |
| [shared-vpc.tf](./shared-vpc.tf) | Shared VPC project-level configuration. | <code>google_compute_shared_vpc_host_project</code> · <code>google_compute_shared_vpc_service_project</code> · <code>google_compute_subnetwork_iam_member</code> · <code>google_project_iam_member</code> |
| [tags.tf](./tags.tf) | None | <code>google_tags_tag_binding</code> · <code>google_tags_tag_key</code> · <code>google_tags_tag_key_iam_binding</code> · <code>google_tags_tag_key_iam_member</code> · <code>google_tags_tag_value</code> · <code>google_tags_tag_value_iam_binding</code> · <code>google_tags_tag_value_iam_member</code> |
| [variables-iam.tf](./variables-iam.tf) | None |  |
| [variables-quotas.tf](./variables-quotas.tf) | None |  |
| [variables-tags.tf](./variables-tags.tf) | None |  |
| [variables.tf](./variables.tf) | Module variables. |  |
| [versions.tf](./versions.tf) | Version pins. |  |
| [vpc-sc.tf](./vpc-sc.tf) | VPC-SC project-level perimeter configuration. | <code>google_access_context_manager_service_perimeter_dry_run_resource</code> · <code>google_access_context_manager_service_perimeter_resource</code> |

## Variables

| name | description | type | required | default |
|---|---|:---:|:---:|:---:|
| [name](variables.tf#L165) | Project name and id suffix. | <code>string</code> | ✓ |  |
| [auto_create_network](variables.tf#L17) | Whether to create the default network for the project. | <code>bool</code> |  | <code>false</code> |
| [billing_account](variables.tf#L23) | Billing account id. | <code>string</code> |  | <code>null</code> |
| [compute_metadata](variables.tf#L29) | Optional compute metadata key/values. Only usable if compute API has been enabled. | <code>map&#40;string&#41;</code> |  | <code>&#123;&#125;</code> |
| [contacts](variables.tf#L36) | List of essential contacts for this resource. Must be in the form EMAIL -> [NOTIFICATION_TYPES]. Valid notification types are ALL, SUSPENSION, SECURITY, TECHNICAL, BILLING, LEGAL, PRODUCT_UPDATES. | <code>map&#40;list&#40;string&#41;&#41;</code> |  | <code>&#123;&#125;</code> |
| [custom_roles](variables.tf#L43) | Map of role name => list of permissions to create in this project. | <code>map&#40;list&#40;string&#41;&#41;</code> |  | <code>&#123;&#125;</code> |
| [default_service_account](variables.tf#L50) | Project default service account setting: can be one of `delete`, `deprivilege`, `disable`, or `keep`. | <code>string</code> |  | <code>&#34;keep&#34;</code> |
| [deletion_policy](variables.tf#L64) | Deletion policy setting for this project. | <code>string</code> |  | <code>&#34;DELETE&#34;</code> |
| [descriptive_name](variables.tf#L75) | Name of the project name. Used for project name instead of `name` variable. | <code>string</code> |  | <code>null</code> |
| [factories_config](variables.tf#L81) | Paths to data files and folders that enable factory functionality. | <code title="object&#40;&#123;&#10;  custom_roles &#61; optional&#40;string&#41;&#10;  org_policies &#61; optional&#40;string&#41;&#10;  quotas       &#61; optional&#40;string&#41;&#10;&#125;&#41;">object&#40;&#123;&#8230;&#125;&#41;</code> |  | <code>&#123;&#125;</code> |
| [iam](variables-iam.tf#L17) | Authoritative IAM bindings in {ROLE => [MEMBERS]} format. | <code>map&#40;list&#40;string&#41;&#41;</code> |  | <code>&#123;&#125;</code> |
| [iam_bindings](variables-iam.tf#L24) | Authoritative IAM bindings in {KEY => {role = ROLE, members = [], condition = {}}}. Keys are arbitrary. | <code title="map&#40;object&#40;&#123;&#10;  members &#61; list&#40;string&#41;&#10;  role    &#61; string&#10;  condition &#61; optional&#40;object&#40;&#123;&#10;    expression  &#61; string&#10;    title       &#61; string&#10;    description &#61; optional&#40;string&#41;&#10;  &#125;&#41;&#41;&#10;&#125;&#41;&#41;">map&#40;object&#40;&#123;&#8230;&#125;&#41;&#41;</code> |  | <code>&#123;&#125;</code> |
| [iam_bindings_additive](variables-iam.tf#L39) | Individual additive IAM bindings. Keys are arbitrary. | <code title="map&#40;object&#40;&#123;&#10;  member &#61; string&#10;  role   &#61; string&#10;  condition &#61; optional&#40;object&#40;&#123;&#10;    expression  &#61; string&#10;    title       &#61; string&#10;    description &#61; optional&#40;string&#41;&#10;  &#125;&#41;&#41;&#10;&#125;&#41;&#41;">map&#40;object&#40;&#123;&#8230;&#125;&#41;&#41;</code> |  | <code>&#123;&#125;</code> |
| [iam_by_principals](variables-iam.tf#L54) | Authoritative IAM binding in {PRINCIPAL => [ROLES]} format. Principals need to be statically defined to avoid cycle errors. Merged internally with the `iam` variable. | <code>map&#40;list&#40;string&#41;&#41;</code> |  | <code>&#123;&#125;</code> |
| [labels](variables.tf#L92) | Resource labels. | <code>map&#40;string&#41;</code> |  | <code>&#123;&#125;</code> |
| [lien_reason](variables.tf#L99) | If non-empty, creates a project lien with this description. | <code>string</code> |  | <code>null</code> |
| [logging_data_access](variables.tf#L105) | Control activation of data access logs. Format is service => { log type => [exempted members]}. The special 'allServices' key denotes configuration for all services. | <code>map&#40;map&#40;list&#40;string&#41;&#41;&#41;</code> |  | <code>&#123;&#125;</code> |
| [logging_exclusions](variables.tf#L120) | Logging exclusions for this project in the form {NAME -> FILTER}. | <code>map&#40;string&#41;</code> |  | <code>&#123;&#125;</code> |
| [logging_sinks](variables.tf#L127) | Logging sinks to create for this project. | <code title="map&#40;object&#40;&#123;&#10;  bq_partitioned_table &#61; optional&#40;bool, false&#41;&#10;  description          &#61; optional&#40;string&#41;&#10;  destination          &#61; string&#10;  disabled             &#61; optional&#40;bool, false&#41;&#10;  exclusions           &#61; optional&#40;map&#40;string&#41;, &#123;&#125;&#41;&#10;  filter               &#61; optional&#40;string&#41;&#10;  iam                  &#61; optional&#40;bool, true&#41;&#10;  type                 &#61; string&#10;  unique_writer        &#61; optional&#40;bool, true&#41;&#10;&#125;&#41;&#41;">map&#40;object&#40;&#123;&#8230;&#125;&#41;&#41;</code> |  | <code>&#123;&#125;</code> |
| [metric_scopes](variables.tf#L158) | List of projects that will act as metric scopes for this project. | <code>list&#40;string&#41;</code> |  | <code>&#91;&#93;</code> |
| [network_tags](variables-tags.tf#L17) | Network tags by key name. If `id` is provided, key creation is skipped. The `iam` attribute behaves like the similarly named one at module level. | <code title="map&#40;object&#40;&#123;&#10;  description &#61; optional&#40;string, &#34;Managed by the Terraform project module.&#34;&#41;&#10;  iam         &#61; optional&#40;map&#40;list&#40;string&#41;&#41;, &#123;&#125;&#41;&#10;  iam_bindings &#61; optional&#40;map&#40;object&#40;&#123;&#10;    members &#61; list&#40;string&#41;&#10;    role    &#61; string&#10;    condition &#61; optional&#40;object&#40;&#123;&#10;      expression  &#61; string&#10;      title       &#61; string&#10;      description &#61; optional&#40;string&#41;&#10;    &#125;&#41;&#41;&#10;  &#125;&#41;&#41;, &#123;&#125;&#41;&#10;  iam_bindings_additive &#61; optional&#40;map&#40;object&#40;&#123;&#10;    member &#61; string&#10;    role   &#61; string&#10;    condition &#61; optional&#40;object&#40;&#123;&#10;      expression  &#61; string&#10;      title       &#61; string&#10;      description &#61; optional&#40;string&#41;&#10;    &#125;&#41;&#41;&#10;  &#125;&#41;&#41;, &#123;&#125;&#41;&#10;  id      &#61; optional&#40;string&#41;&#10;  network &#61; string &#35; project_id&#47;vpc_name&#10;  values &#61; optional&#40;map&#40;object&#40;&#123;&#10;    description &#61; optional&#40;string, &#34;Managed by the Terraform project module.&#34;&#41;&#10;    iam         &#61; optional&#40;map&#40;list&#40;string&#41;&#41;, &#123;&#125;&#41;&#10;    iam_bindings &#61; optional&#40;map&#40;object&#40;&#123;&#10;      members &#61; list&#40;string&#41;&#10;      role    &#61; string&#10;      condition &#61; optional&#40;object&#40;&#123;&#10;        expression  &#61; string&#10;        title       &#61; string&#10;        description &#61; optional&#40;string&#41;&#10;      &#125;&#41;&#41;&#10;    &#125;&#41;&#41;, &#123;&#125;&#41;&#10;    iam_bindings_additive &#61; optional&#40;map&#40;object&#40;&#123;&#10;      member &#61; string&#10;      role   &#61; string&#10;      condition &#61; optional&#40;object&#40;&#123;&#10;        expression  &#61; string&#10;        title       &#61; string&#10;        description &#61; optional&#40;string&#41;&#10;      &#125;&#41;&#41;&#10;    &#125;&#41;&#41;, &#123;&#125;&#41;&#10;  &#125;&#41;&#41;, &#123;&#125;&#41;&#10;&#125;&#41;&#41;">map&#40;object&#40;&#123;&#8230;&#125;&#41;&#41;</code> |  | <code>&#123;&#125;</code> |
| [org_policies](variables.tf#L170) | Organization policies applied to this project keyed by policy name. | <code title="map&#40;object&#40;&#123;&#10;  inherit_from_parent &#61; optional&#40;bool&#41; &#35; for list policies only.&#10;  reset               &#61; optional&#40;bool&#41;&#10;  rules &#61; optional&#40;list&#40;object&#40;&#123;&#10;    allow &#61; optional&#40;object&#40;&#123;&#10;      all    &#61; optional&#40;bool&#41;&#10;      values &#61; optional&#40;list&#40;string&#41;&#41;&#10;    &#125;&#41;&#41;&#10;    deny &#61; optional&#40;object&#40;&#123;&#10;      all    &#61; optional&#40;bool&#41;&#10;      values &#61; optional&#40;list&#40;string&#41;&#41;&#10;    &#125;&#41;&#41;&#10;    enforce &#61; optional&#40;bool&#41; &#35; for boolean policies only.&#10;    condition &#61; optional&#40;object&#40;&#123;&#10;      description &#61; optional&#40;string&#41;&#10;      expression  &#61; optional&#40;string&#41;&#10;      location    &#61; optional&#40;string&#41;&#10;      title       &#61; optional&#40;string&#41;&#10;    &#125;&#41;, &#123;&#125;&#41;&#10;  &#125;&#41;&#41;, &#91;&#93;&#41;&#10;&#125;&#41;&#41;">map&#40;object&#40;&#123;&#8230;&#125;&#41;&#41;</code> |  | <code>&#123;&#125;</code> |
| [parent](variables.tf#L197) | Parent folder or organization in 'folders/folder_id' or 'organizations/org_id' format. | <code>string</code> |  | <code>null</code> |
| [prefix](variables.tf#L207) | Optional prefix used to generate project id and name. | <code>string</code> |  | <code>null</code> |
| [project_create](variables.tf#L217) | Create project. When set to false, uses a data source to reference existing project. | <code>bool</code> |  | <code>true</code> |
| [quotas](variables-quotas.tf#L17) | Service quota configuration. | <code title="map&#40;object&#40;&#123;&#10;  service              &#61; string&#10;  quota_id             &#61; string&#10;  preferred_value      &#61; number&#10;  dimensions           &#61; optional&#40;map&#40;string&#41;, &#123;&#125;&#41;&#10;  justification        &#61; optional&#40;string&#41;&#10;  contact_email        &#61; optional&#40;string&#41;&#10;  annotations          &#61; optional&#40;map&#40;string&#41;&#41;&#10;  ignore_safety_checks &#61; optional&#40;string&#41;&#10;&#125;&#41;&#41;">map&#40;object&#40;&#123;&#8230;&#125;&#41;&#41;</code> |  | <code>&#123;&#125;</code> |
| [service_agents_config](variables.tf#L223) | Automatic service agent configuration options. | <code title="object&#40;&#123;&#10;  create_primary_agents &#61; optional&#40;bool, true&#41;&#10;  grant_default_roles   &#61; optional&#40;bool, true&#41;&#10;  services_enabled      &#61; optional&#40;list&#40;string&#41;, &#91;&#93;&#41;&#10;&#125;&#41;">object&#40;&#123;&#8230;&#125;&#41;</code> |  | <code>&#123;&#125;</code> |
| [service_config](variables.tf#L234) | Configure service API activation. | <code title="object&#40;&#123;&#10;  disable_on_destroy         &#61; bool&#10;  disable_dependent_services &#61; bool&#10;&#125;&#41;">object&#40;&#123;&#8230;&#125;&#41;</code> |  | <code title="&#123;&#10;  disable_on_destroy         &#61; false&#10;  disable_dependent_services &#61; false&#10;&#125;">&#123;&#8230;&#125;</code> |
| [service_encryption_key_ids](variables.tf#L246) | Service Agents to be granted encryption/decryption permissions over Cloud KMS encryption keys. Format {SERVICE_AGENT => [KEY_ID]}. | <code>map&#40;list&#40;string&#41;&#41;</code> |  | <code>&#123;&#125;</code> |
| [services](variables.tf#L253) | Service APIs to enable. | <code>list&#40;string&#41;</code> |  | <code>&#91;&#93;</code> |
| [shared_vpc_host_config](variables.tf#L259) | Configures this project as a Shared VPC host project (mutually exclusive with shared_vpc_service_project). | <code title="object&#40;&#123;&#10;  enabled          &#61; bool&#10;  service_projects &#61; optional&#40;list&#40;string&#41;, &#91;&#93;&#41;&#10;&#125;&#41;">object&#40;&#123;&#8230;&#125;&#41;</code> |  | <code>null</code> |
| [shared_vpc_service_config](variables.tf#L268) | Configures this project as a Shared VPC service project (mutually exclusive with shared_vpc_host_config). | <code title="object&#40;&#123;&#10;  host_project             &#61; string&#10;  network_users            &#61; optional&#40;list&#40;string&#41;, &#91;&#93;&#41;&#10;  service_agent_iam        &#61; optional&#40;map&#40;list&#40;string&#41;&#41;, &#123;&#125;&#41;&#10;  service_agent_subnet_iam &#61; optional&#40;map&#40;list&#40;string&#41;&#41;, &#123;&#125;&#41;&#10;  service_iam_grants       &#61; optional&#40;list&#40;string&#41;, &#91;&#93;&#41;&#10;  network_subnet_users     &#61; optional&#40;map&#40;list&#40;string&#41;&#41;, &#123;&#125;&#41;&#10;&#125;&#41;">object&#40;&#123;&#8230;&#125;&#41;</code> |  | <code title="&#123;&#10;  host_project &#61; null&#10;&#125;">&#123;&#8230;&#125;</code> |
| [skip_delete](variables.tf#L296) | Deprecated. Use deletion_policy. | <code>bool</code> |  | <code>null</code> |
| [tag_bindings](variables-tags.tf#L81) | Tag bindings for this project, in key => tag value id format. | <code>map&#40;string&#41;</code> |  | <code>null</code> |
| [tags](variables-tags.tf#L88) | Tags by key name. If `id` is provided, key or value creation is skipped. The `iam` attribute behaves like the similarly named one at module level. | <code title="map&#40;object&#40;&#123;&#10;  description &#61; optional&#40;string, &#34;Managed by the Terraform project module.&#34;&#41;&#10;  iam         &#61; optional&#40;map&#40;list&#40;string&#41;&#41;, &#123;&#125;&#41;&#10;  iam_bindings &#61; optional&#40;map&#40;object&#40;&#123;&#10;    members &#61; list&#40;string&#41;&#10;    role    &#61; string&#10;    condition &#61; optional&#40;object&#40;&#123;&#10;      expression  &#61; string&#10;      title       &#61; string&#10;      description &#61; optional&#40;string&#41;&#10;    &#125;&#41;&#41;&#10;  &#125;&#41;&#41;, &#123;&#125;&#41;&#10;  iam_bindings_additive &#61; optional&#40;map&#40;object&#40;&#123;&#10;    member &#61; string&#10;    role   &#61; string&#10;    condition &#61; optional&#40;object&#40;&#123;&#10;      expression  &#61; string&#10;      title       &#61; string&#10;      description &#61; optional&#40;string&#41;&#10;    &#125;&#41;&#41;&#10;  &#125;&#41;&#41;, &#123;&#125;&#41;&#10;  id &#61; optional&#40;string&#41;&#10;  values &#61; optional&#40;map&#40;object&#40;&#123;&#10;    description &#61; optional&#40;string, &#34;Managed by the Terraform project module.&#34;&#41;&#10;    iam         &#61; optional&#40;map&#40;list&#40;string&#41;&#41;, &#123;&#125;&#41;&#10;    iam_bindings &#61; optional&#40;map&#40;object&#40;&#123;&#10;      members &#61; list&#40;string&#41;&#10;      role    &#61; string&#10;      condition &#61; optional&#40;object&#40;&#123;&#10;        expression  &#61; string&#10;        title       &#61; string&#10;        description &#61; optional&#40;string&#41;&#10;      &#125;&#41;&#41;&#10;    &#125;&#41;&#41;, &#123;&#125;&#41;&#10;    iam_bindings_additive &#61; optional&#40;map&#40;object&#40;&#123;&#10;      member &#61; string&#10;      role   &#61; string&#10;      condition &#61; optional&#40;object&#40;&#123;&#10;        expression  &#61; string&#10;        title       &#61; string&#10;        description &#61; optional&#40;string&#41;&#10;      &#125;&#41;&#41;&#10;    &#125;&#41;&#41;, &#123;&#125;&#41;&#10;    id &#61; optional&#40;string&#41;&#10;  &#125;&#41;&#41;, &#123;&#125;&#41;&#10;&#125;&#41;&#41;">map&#40;object&#40;&#123;&#8230;&#125;&#41;&#41;</code> |  | <code>&#123;&#125;</code> |
| [vpc_sc](variables.tf#L308) | VPC-SC configuration for the project, use when `ignore_changes` for resources is set in the VPC-SC module. | <code title="object&#40;&#123;&#10;  perimeter_name    &#61; string&#10;  perimeter_bridges &#61; optional&#40;list&#40;string&#41;, &#91;&#93;&#41;&#10;  is_dry_run        &#61; optional&#40;bool, false&#41;&#10;&#125;&#41;">object&#40;&#123;&#8230;&#125;&#41;</code> |  | <code>null</code> |

## Outputs

| name | description | sensitive |
|---|---|:---:|
| [custom_role_id](outputs.tf#L17) | Map of custom role IDs created in the project. |  |
| [custom_roles](outputs.tf#L27) | Map of custom roles resources created in the project. |  |
| [default_service_accounts](outputs.tf#L33) | Emails of the default service accounts for this project. |  |
| [id](outputs.tf#L41) | Project id. |  |
| [name](outputs.tf#L59) | Project name. |  |
| [network_tag_keys](outputs.tf#L71) | Tag key resources. |  |
| [network_tag_values](outputs.tf#L80) | Tag value resources. |  |
| [number](outputs.tf#L88) | Project number. |  |
| [project_id](outputs.tf#L106) | Project id. |  |
| [quota_configs](outputs.tf#L124) | Quota configurations. |  |
| [quotas](outputs.tf#L135) | Quota resources. |  |
| [service_agents](outputs.tf#L140) | List of all (active) service agents for this project. |  |
| [services](outputs.tf#L149) | Service APIs to enabled in the project. |  |
| [sink_writer_identities](outputs.tf#L158) | Writer identities created for each sink. |  |
| [tag_keys](outputs.tf#L165) | Tag key resources. |  |
| [tag_values](outputs.tf#L174) | Tag value resources. |  |
<!-- END TFDOC -->