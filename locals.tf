locals {
  common_tags = {
    env           = var.env
    project       = "roboshop"
    business_unit = "ecommerce"
    owner         = "ecommerce-robot"
  }
  all_tags = merge(
    local.common_tags,
    { Name = "${var.env}-${var.component}-asg" }
  )
}

