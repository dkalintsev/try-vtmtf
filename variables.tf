variable "vtm_rest_ip" {
  description = "IP or FQDN of the vTM REST API endpoint, e.g. '192.168.0.1'"
}

variable "vtm_rest_port" {
  description = "TCP port of the vTM REST API endpoint"
  default     = "9070"
}

variable "vtm_username" {
  description = "Username to use for connecting to the vTM"
  default     = "admin"
}

variable "vtm_password" {
  description = "Password of the $vtm_username account on the vTM"
}

variable "main_nodes" {
  description = "List of nodes for the 'Main' pool"

  # For example, ["1.1.1.1:80", "2.2.2.2:80"]
  default = []
}

variable "api_nodes" {
  description = "List of nodes for the 'API' pool"
  default     = []
}

variable "vtm_tig_eips" {
  description = "List of AWS Elastic IPs to be used for Traffic IP Group"
  default     = []
}

variable "ssl_cert_pri" {
  description = "Private SSL Cert for the Virtual Server"
}

variable "ssl_cert_pub" {
  description = "Public SSL Cert for the Virtual Server"
}

variable "ssl_cert_req" {
  description = "Signing Request for the SSL Cert for the Virtual Server"
}
