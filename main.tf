locals {
  all_project_services = concat(var.gcp_service_list, [
    "storage.googleapis.com",
    "appengine.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "cloudbuild.googleapis.com",

  ])
}

resource "google_project_service" "enabled_apis" {
  project                    = var.project_id
  for_each                   = toset(local.all_project_services)
  service                    = each.key
  disable_dependent_services = true
  disable_on_destroy         = true
}

resource "time_sleep" "wait_project_init" {
  create_duration = "90s"

  depends_on = [google_project_service.enabled_apis]
}

resource "google_storage_bucket" "app" {
  name          = "${var.name}-${random_id.app.hex}"
  location      = "US"
  force_destroy = true
  versioning {
    enabled = true
  }
  depends_on = [google_project_service.enabled_apis, time_sleep.wait_project_init]
}

resource "random_id" "app" {
  byte_length = 8
  depends_on  = [google_project_service.enabled_apis, time_sleep.wait_project_init]
}

data "archive_file" "function_dist" {
  type        = "zip"
  source_dir  = "python"
  output_path = "python/app.zip"
  depends_on  = [google_project_service.enabled_apis, time_sleep.wait_project_init]
}

resource "google_storage_bucket_object" "app" {
  name       = "app.zip"
  source     = data.archive_file.function_dist.output_path
  bucket     = google_storage_bucket.app.name
  depends_on = [google_project_service.enabled_apis, time_sleep.wait_project_init]
}

resource "google_app_engine_application" "app" {
  location_id = "us-central"
  depends_on  = [google_storage_bucket_object.app, google_project_service.enabled_apis, time_sleep.wait_project_init]
}

resource "google_app_engine_standard_app_version" "latest_version" {

  version_id = var.deployment_version
  service    = "default"
  runtime    = "python312"

  entrypoint {
    shell = "python main.py"
  }

  deployment {
    zip {
      source_url = "https://storage.googleapis.com/${google_storage_bucket.app.name}/${google_storage_bucket_object.app.name}"
    }
  }

  instance_class = "F1"

  automatic_scaling {
    max_concurrent_requests = 10
    min_idle_instances      = 1
    max_idle_instances      = 1
    min_pending_latency     = "1s"
    max_pending_latency     = "5s"
    standard_scheduler_settings {
      target_cpu_utilization        = 0.5
      target_throughput_utilization = 0.75
      min_instances                 = 0
      max_instances                 = 4
    }
  }
  noop_on_destroy           = true
  delete_service_on_destroy = true

  depends_on = [google_app_engine_application.app, google_project_service.enabled_apis, time_sleep.wait_project_init]
}