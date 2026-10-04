terraform {
  backend "s3" {
    bucket       = "togglemaster-tfstate-583383233548"
    key          = "platform/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}
