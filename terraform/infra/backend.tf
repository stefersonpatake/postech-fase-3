terraform {
  backend "s3" {
    # Bucket criado por terraform/bootstrap/bootstrap.sh (<project>-tfstate-<account_id>).
    bucket       = "togglemaster-tfstate-583383233548"
    key          = "infra/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}
