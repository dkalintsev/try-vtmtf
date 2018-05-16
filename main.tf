provider "vtm" {
  base_url        = "https://${var.vtm_rest_ip}:${var.vtm_rest_port}/api"
  username        = "${var.vtm_username}"
  password        = "${var.vtm_password}"
  verify_ssl_cert = false
  version         = "~> 4.0.0"
}

# Random string to make sure each deployment of this template
# includes unique string in all resources' names. This should allow
# deployment of more than one copy of this template to the same vTM
# cluster as long as the unique things like IP addresses used for
# Traffic IP Groups are taken care of elsewhere.
#
resource "random_string" "instance_id" {
  length  = 4
  special = false
  upper   = false
}

locals {
  # Create a local var with the value of the random instance_id
  uniq_id = "${random_string.instance_id.result}"
}

# An example of a pool with static nodes. Let's *not* do that. :)
#
/*
resource "vtm_pool" "main_pool" {
  name     = "${local.uniq_id}_Main-Pool"
  monitors = ["Ping"]

  nodes_table {
    node = "10.1.0.10:80"
  }

  nodes_table {
    node = "10.2.0.10:80"
  }
}
*/

data "vtm_pool_nodes_table_table" "main_pool_nodes" {
  # Repeat as many times as we have nodes in our node list variable
  count = "${length(var.main_nodes)}"

  # Get the node from the var.main_nodes list
  node = "${var.main_nodes[count.index]}"

  state = "active"
}

resource "vtm_pool" "main_pool" {
  name     = "${local.uniq_id}_Main-Pool"
  monitors = ["Ping"]

  # The data.vtm_pool_nodes_table_table.main_pool_nodes.*.json returns a list
  # of string, each string is a JSON for one node. We need to wrap this into
  # a JSON list, so we add "[]" at the ends, and join the node strings with ","
  # in the middle for a resulting "[{..},{..}]" string that nodes_table_json
  # is expecting
  #
  nodes_table_json = "[${join(",", data.vtm_pool_nodes_table_table.main_pool_nodes.*.json)}]"
}

data "vtm_pool_nodes_table_table" "api_pool_nodes" {
  count    = "${length(var.api_nodes)}"
  node     = "${var.api_nodes[count.index]}"
  priority = "1"
  state    = "active"
  weight   = "1"
}

resource "vtm_pool" "api_pool" {
  name             = "${local.uniq_id}_API-Pool"
  monitors         = ["Ping"]
  nodes_table_json = "[${join(",", data.vtm_pool_nodes_table_table.api_pool_nodes.*.json)}]"
}

# This returns a list populated with "name" values of all traffic managers
# in the target cluster. We need this to create the Traffic IP Group.
#
data "vtm_traffic_manager_list" "cluster_machines" {
  # No parameters needed
}

locals {
  tig_name = "${local.uniq_id}_TrafficIPGroup"
}

# Traffic IP Group for our Virtual Server.
# By default, we create the "singlehosted" type.
#
resource "vtm_traffic_ip_group" "tip_group" {
  count       = "${signum(length(var.vtm_tig_eips))}"
  name        = "${local.tig_name}"
  mode        = "ec2vpcelastic"
  ipaddresses = "${var.vtm_tig_eips}"
  machines    = ["${data.vtm_traffic_manager_list.cluster_machines.object_list}"]
}

locals {
  # If var.vtm_tig_eips is empty, we should not use TIP Group
  should_listen_on_any = "${length(var.vtm_tig_eips) == 0 ? true : false}"

  # This is to provide the list of TIP Group Names to listen_on_traffic_ips
  # paremeter of the Virtual Server. If We don't have any Traffic IPs, this
  # list should be empty; if we do - it should have a name of our TIP Group.
  tigs_list = ["${length(var.vtm_tig_eips) == 0 ? "" : local.tig_name}"]
}

# The Virtual Server
#
resource "vtm_virtual_server" "vs1" {
  name          = "${local.uniq_id}_VS1"
  enabled       = "true"
  listen_on_any = "${local.should_listen_on_any}"

  # We need to use compact() to get rid of values "" which will be there
  # in case we didn't have any TIP Groups
  listen_on_traffic_ips = ["${compact(local.tigs_list)}"]

  # Default pool = "Main"
  pool                    = "${vtm_pool.main_pool.name}"
  port                    = "443"
  protocol                = "http"
  ssl_decrypt             = "true"
  ssl_server_cert_default = "${vtm_ssl_server_key.ssl_cert.name}"
  request_rules           = ["${vtm_rule.vs1_l7_routes.name}"]
}

# Our Request Rule needs API pool name, so we handle this through a template
data "template_file" "vs1_request_rule" {
  template = "${file("${path.module}/files/vs1_request_rule.tpl")}"

  vars {
    pool_name = "${vtm_pool.api_pool.name}"
  }
}

resource "vtm_rule" "vs1_l7_routes" {
  name    = "${local.uniq_id}_VS1-L7-Routes"
  content = "${data.template_file.vs1_request_rule.rendered}"
}

# Alternative way of implementing the rule - using heredoc. This would replace
# the data template_file + resource vtm_rule above.
#
/*
resource "vtm_rule" "vs1_l7_routes" {
  name = "${local.uniq_id}_VS1-L7-Routes"

  # Content is TrafficScript, with an embedded Terraform variable
  #
  content = <<EOF
if(http.getPath() == "/api") {
    pool.use("${vtm_pool.api_pool.name}");
}
EOF
}
*/

# SSL Server Certificates for the Virtual Server's SSL Offload.
#
resource "vtm_ssl_server_key" "ssl_cert" {
  name = "${local.uniq_id}-server-corp.com"
  note = "SSL Server Cert for corp.com"

  private = "${var.ssl_cert_pri}"
  public  = "${var.ssl_cert_pub}"
  request = "${var.ssl_cert_req}"
}
