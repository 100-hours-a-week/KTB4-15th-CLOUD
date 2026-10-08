terraform {
  backend "s3" {
    bucket       = "lookddak-terraform-state-686496667254"
    key          = "terraform.tfstate"
    region       = "ap-northeast-2"
    encrypt      = true
    use_lockfile = true
  }
}