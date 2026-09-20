variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "availability_zone" {
  description = "Pin the instance to one AZ (spot capacity for metal varies by AZ). Empty = first default subnet."
  type        = string
  default     = ""
}

variable "instance_type" {
  description = "Bare-metal AMD EPYC instance to benchmark on"
  type        = string
  default     = "c7a.metal-48xl"
}

variable "use_spot" {
  description = "Launch as a one-time spot instance (~70% cheaper, interruptible)"
  type        = bool
  default     = true
}

variable "spot_max_price" {
  description = "Max spot price in USD/hr. Empty = on-demand price cap (AWS default)."
  type        = string
  default     = ""
}

variable "name" {
  description = "Name tag / hostname prefix"
  type        = string
  default     = "amd-lowlat-bench"
}

variable "ssh_public_key_path" {
  description = "Public key injected into the instance"
  type        = string
  default     = "~/.ssh/id_ed25519.pub"
}

variable "ssh_private_key_path" {
  description = "Matching private key, written into the generated Ansible inventory"
  type        = string
  default     = "~/.ssh/id_ed25519"
}

variable "ssh_allowed_cidrs" {
  description = "CIDRs allowed to SSH. Empty = your current public IP only."
  type        = list(string)
  default     = []
}

variable "root_volume_gb" {
  description = "Root EBS volume size (gp3)"
  type        = number
  default     = 50
}

variable "ami_id" {
  description = "Override the AMI. Empty = latest official Rocky Linux 9 x86_64 AMI."
  type        = string
  default     = ""
}

variable "inventory_path" {
  description = "Where to write the Ansible inventory (relative to this directory)"
  type        = string
  default     = "../inventory/hosts.ini"
}
