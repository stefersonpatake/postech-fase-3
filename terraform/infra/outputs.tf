output "account_id" {
  value = data.aws_caller_identity.current.account_id
}

output "lab_role_arn" {
  value = data.aws_iam_role.lab.arn
}
