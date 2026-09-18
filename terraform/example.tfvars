# Copy this file to terraform.tfvars and adjust before your first apply.
# Every variable here has a working default (see variables.tf) — this file
# only exists to surface the ones most likely to need changing, based on
# real constraints hit while building this project (see README →
# Challenges and Troubleshooting, #1 and #2).

# southindia does NOT support availability-zone-pinned node pools. If you
# pick a different region, confirm zone support before adding `zones` back
# into the cluster resources — it was removed here specifically because
# this region doesn't support it, not because zoning is a bad idea.
location = "southindia"

# Standard_D2ds_v6 was chosen because it was the first VM family with
# actual usable quota on the subscription this was built on — not a
# recommendation. Azure Free Trial subscriptions carry a hard 4 vCPU
# regional cap; even Pay-As-You-Go often starts with 0 quota on specific
# VM families regardless of the regional total. Before changing this,
# check quota for the EXACT family, not just the region:
#   az vm list-usage --location <region> -o table
node_size = "Standard_D2ds_v6"

# Change this if you're running multiple copies of this stack in the same
# subscription (e.g. testing alongside a colleague) — it's also the
# cleanup boundary: `terraform destroy` only removes what's inside it.
resource_group_name = "rg-obs-day2"
