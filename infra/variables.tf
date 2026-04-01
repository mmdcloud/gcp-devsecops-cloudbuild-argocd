variable "project_id" {
  type    = string
  default = ""
}

variable "env" {
  type    = string
  default = ""
}

variable "region" {
  type    = string
  default = ""
}

variable "node_pools" {
  description = "Map of node pool configurations"
  type = map(object({
    machine_type = string
    disk_size_gb = number
    min_nodes    = number
    max_nodes    = number
    preemptible  = bool
    gpu_count    = number
    gpu_type     = string
    taints = list(object({
      key    = string
      value  = string
      effect = string
    }))
  }))

  default = {}

  validation {
    condition = alltrue([
      for k, v in var.node_pools :
      v.gpu_count == 0 || v.gpu_type != ""
    ])
    error_message = "gpu_type must be set when gpu_count > 0."
  }

  validation {
    condition = alltrue([
      for k, v in var.node_pools :
      contains(["NO_SCHEDULE", "PREFER_NO_SCHEDULE", "NO_EXECUTE"], v.taints[*].effect...)
      if length(v.taints) > 0
    ])
    error_message = "Taint effect must be one of NO_SCHEDULE, PREFER_NO_SCHEDULE, NO_EXECUTE."
  }
}