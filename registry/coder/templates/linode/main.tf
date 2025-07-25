terraform {
  required_providers {
    coder = {
      source = "coder/coder"
    }
    linode = {
      source  = "linode/linode"
    }
  }
}

locals {
  username = data.coder_workspace_owner.me.name
}

variable "linode_token" {
  type = string
  description = "Your Linode Token"
  default = "null"
}

variable "region" {
  type = string
  description = "Where do you want your linode instance to be hosted?"
  default = "us-central"
}

provider "linode" {
  token = var.linode_token
}

data "coder_provisioner" "me" {}
data "coder_workspace" "me" {}
data "coder_workspace_owner" "me" {}

resource "linode_instance" "main" {
  region = data.coder_parameter.region.value
  label = "linode-${data.coder_workspace.me.id}-home" 
  type = data.coder_parameter.type.value
}

resource "linode_instance_disk" "boot" {
  label = "boot"
  linode_id = linode_instance.main.id
  size = tostring(data.coder_parameter.storage_size)
  # this is making me aggrovated, I can't figure out how to convert this value gathered later on (in create workspace vs. import template) to a string so TF will accept it.
  filesystem = "ext4"
}

data "coder_parameter" "region" {
  name         = "region"
  display_name = "Region"
  description  = "This is the region where your workspace will be created."
  type         = "string"
  default      = "us-central"
  mutable      = false
  option {
    name  = "Dallas, TX"
    value = "us-central"
  }
  option {
    name  = "Fremont, CA"
    value = "us-west"
  }
  option {
    name  = "Atlanta, GA"
    value = "us-southeast"
  }
  option {
    name = "Newark, NJ"
    value= "us-east"
  }
}

data "coder_parameter" "type" {
  name = "type"
  display_name = "Instance Type"
  type = "string"
  default = "g6-standard-2"
  # Linode documentation does not specify a list of types, so I'm not sure what to put here. I'm not currently a Linode customer.
}

data "coder_parameter" "storage_size" {
  name = "storage_size"
  display_name = "Storage Size"
  type = "number"
  default = "25"
}

resource "coder_agent" "main" {
  arch           = data.coder_provisioner.me.arch
  os             = "linux"
  startup_script = <<-EOT
    set -e

    # Prepare user home with default files on first start.
    if [ ! -f ~/.init_done ]; then
      cp -rT /etc/skel ~
      touch ~/.init_done
    fi

    # Add any commands that should be executed at workspace startup (e.g install requirements, start a program, etc) here
  EOT

  # These environment variables allow you to make Git commits right away after creating a
  # workspace. Note that they take precedence over configuration defined in ~/.gitconfig!
  # You can remove this block if you'd prefer to configure Git manually or using
  # dotfiles. (see docs/dotfiles.md)
  env = {
    GIT_AUTHOR_NAME     = coalesce(data.coder_workspace_owner.me.full_name, data.coder_workspace_owner.me.name)
    GIT_AUTHOR_EMAIL    = "${data.coder_workspace_owner.me.email}"
    GIT_COMMITTER_NAME  = coalesce(data.coder_workspace_owner.me.full_name, data.coder_workspace_owner.me.name)
    GIT_COMMITTER_EMAIL = "${data.coder_workspace_owner.me.email}"
  }

  # The following metadata blocks are optional. They are used to display
  # information about your workspace in the dashboard. You can remove them
  # if you don't want to display any information.
  # For basic resources, you can use the `coder stat` command.
  # If you need more control, you can write your own script.
  metadata {
    display_name = "CPU Usage"
    key          = "0_cpu_usage"
    script       = "coder stat cpu"
    interval     = 10
    timeout      = 1
  }

  metadata {
    display_name = "RAM Usage"
    key          = "1_ram_usage"
    script       = "coder stat mem"
    interval     = 10
    timeout      = 1
  }

  metadata {
    display_name = "Home Disk"
    key          = "3_home_disk"
    script       = "coder stat disk --path $${HOME}"
    interval     = 60
    timeout      = 1
  }

  metadata {
    display_name = "CPU Usage (Host)"
    key          = "4_cpu_usage_host"
    script       = "coder stat cpu --host"
    interval     = 10
    timeout      = 1
  }

  metadata {
    display_name = "Memory Usage (Host)"
    key          = "5_mem_usage_host"
    script       = "coder stat mem --host"
    interval     = 10
    timeout      = 1
  }

  metadata {
    display_name = "Load Average (Host)"
    key          = "6_load_host"
    # get load avg scaled by number of cores
    script   = <<EOT
      echo "`cat /proc/loadavg | awk '{ print $1 }'` `nproc`" | awk '{ printf "%0.2f", $1/$2 }'
    EOT
    interval = 60
    timeout  = 1
  }

  metadata {
    display_name = "Swap Usage (Host)"
    key          = "7_swap_host"
    script       = <<EOT
      free -b | awk '/^Swap/ { printf("%.1f/%.1f", $3/1024.0/1024.0/1024.0, $2/1024.0/1024.0/1024.0) }'
    EOT
    interval     = 10
    timeout      = 1
  }
}

# See https://registry.coder.com/modules/coder/code-server
module "code-server" {
  count  = data.coder_workspace.me.start_count
  source = "registry.coder.com/coder/code-server/coder"

  # This ensures that the latest non-breaking version of the module gets downloaded, you can also pin the module version to prevent breaking changes in production.
  version = "~> 1.0"

  agent_id = coder_agent.main.id
  order    = 1
}
