resource "terraform_data" "configuration_guard" {
  lifecycle {
    # Identical address spaces cannot be peered or reliably resolved. Broader
    # overlap detection is deliberately not attempted: Terraform has no native
    # CIDR containment function, and hand-rolled address math in a lab scaffold
    # would be more likely to be wrong than useful. Confirm non-overlap against
    # the real IPAM before applying this anywhere that matters.
    precondition {
      condition     = var.hub_address_space != var.spoke_address_space
      error_message = "hub_address_space and spoke_address_space must differ."
    }
  }
}
