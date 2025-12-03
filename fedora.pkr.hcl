variable "open_console" {
  default = false
}

variable "user_name" {
  default = "fedora"
}

variable "user_pass" {
  default = "asdf"
}

build {
  name    = "fedora"
  sources = ["source.qemu.fedora"]

  # actual configuration goes here, ansible or such
  #provisioner "shell" {
  #  inline = [
  #    "sudo dnf install -y nomad", # consul vault",
  #    "sudo systemctl enable nomad",
  #    # do more stuff here, if you want
  #  ]
  #}
}

locals {
  is_mac       = !fileexists("/etc/os-release")      # lazy, assume mac if not linux
  cpu_arch     = local.is_mac ? "aarch64" : "x86_64" # assume arm chips on mac
  accelerator  = local.is_mac ? "hvf" : "kvm"
  machine_type = local.is_mac ? "virt" : "q35"
  # images: https://fedoraproject.org/cloud/download/
  image_url = "https://download.fedoraproject.org/pub/fedora/linux/releases/43/Cloud/${local.cpu_arch}/images/Fedora-Cloud-Base-Generic-43-1.6.${local.cpu_arch}.qcow2"
  checksum  = local.is_mac ? "66031aea9ec61e6d0d5bba12b9454e80ca94e8a79c913d37ded4c60311705b8b" : "846574c8a97cd2d8dc1f231062d73107cc85cbbbda56335e264a46e3a6c8ab2f"
}

# https://developer.hashicorp.com/packer/integrations/hashicorp/qemu/latest/components/builder/qemu
source "qemu" "fedora" {
  # runtime
  qemu_binary  = "qemu-system-${local.cpu_arch}"
  machine_type = local.machine_type
  accelerator  = local.accelerator

  # source image
  iso_url              = local.image_url
  iso_checksum         = "sha256:${local.checksum}"
  iso_target_path      = abspath("./images")
  iso_target_extension = "qcow2"
  disk_image           = true # our image is already a bootable qemu image (not an ISO)

  # output
  use_backing_file = true # produce a thin copy, requires disk_image = true
  output_directory = "packer-out"
  vm_name          = "fedora.qcow2" # filename
  format           = "qcow2"
  disk_size        = "5G"

  # cloud-init
  cd_label = "cidata"
  cd_content = {
    "user-data" : local.cloud_config,         # see locals{} below
    "meta-data" : "instance-id: fedora-qemu", # minimum required
  }

  # ssh for provisioner(s)
  ssh_timeout  = "2m"
  ssh_username = var.user_name
  ssh_password = var.user_pass

  # misc
  headless         = ! var.open_console
  display          = local.is_mac ? "cocoa" : "gtk"
  boot_wait        = "-1s" # we're not using a boot_command, so no need to wait
  shutdown_command = "echo '${var.user_pass}' | sudo -S shutdown -P now"
}

locals {
  # https://cloudinit.readthedocs.io/en/latest/reference/modules.html
  cloud_config = <<-EOF
#cloud-config

ssh_pwauth: true
users:
 - name: ${var.user_name}
   groups: wheel
   hashed_passwd: ${bcrypt(var.user_pass)} # equiv: mkpasswd -m sha-512
   lock_passwd: false
   sudo: ALL=(ALL) NOPASSWD:ALL

# these land in /etc/yum.sources.d/
yum_repos:
  # https://rpm.releases.hashicorp.com/fedora/hashicorp.repo
  hashicorp:
    name: Hashicorp Stable - $basearch
    baseurl: https://rpm.releases.hashicorp.com/fedora/$releasever/$basearch/stable
    enabled: 1
    gpgcheck: 1
    gpgkey: https://rpm.releases.hashicorp.com/gpg
EOF
}

# this is so `packer init` can fetch the plugin
packer {
  required_plugins {
    qemu = {
      version = "~> 1"
      source  = "github.com/hashicorp/qemu"
    }
  }
}

## misc discarded ideas, kept down here for posterity

## try-hard method to automatically get the checksum
## I don't love needing the http data source
#data "http" "checksum" {
#  url = "https://download.fedoraproject.org/pub/fedora/linux/releases/43/Cloud/${local.cpu_arch}/images/Fedora-Cloud-43-1.6-${local.cpu_arch}-CHECKSUM"
#}
#locals {
#  checksum = regex("qcow2\\) = (.*)", data.http.checksum.body)[0]
#}

## more convoluted cloud-init option:
#http_directory = "http"  # hosts http/user-data, etc
#qemuargs = [
#  ["-smbios", "type=1,serial=ds=nocloud;seedfrom=http://{{ .HTTPIP }}:{{ .HTTPPort }}"],
#]

# also: https://dev.to/miry/getting-started-with-packer-in-2024-56d5

