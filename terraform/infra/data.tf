# AWS Academy: não é permitido criar IAM. Toda role vem da LabRole existente.
data "aws_iam_role" "lab" {
  name = "LabRole"
}

data "aws_caller_identity" "current" {}
