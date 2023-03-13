data "aws_kms_key" "key" {
  key_id = "alias/roboshop"
}

data "aws_ami" "centos8" {
  most_recent = true
  name_regex  = "Centos-8-DevOps-Practice"
  owners      = ["973714476881"]
}
