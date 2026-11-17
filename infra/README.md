# Infrastructure sketch

This directory is a minimal EKS-shaped Terraform configuration for review.

It is not applied. Do not run `terraform apply` or `terraform plan`.
Those commands call AWS. The checks for this repository are `terraform fmt`
and `terraform validate` only. Validate downloads the provider plugin from
the Terraform registry and does not create cloud resources.

There is no remote backend and no credentials file in this repository.
