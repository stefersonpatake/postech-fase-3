resource "aws_dynamodb_table" "this" {
  name         = var.table_name
  billing_mode = "PAY_PER_REQUEST" # sem capacidade provisionada: paga só pelo uso
  hash_key     = var.hash_key

  attribute {
    name = var.hash_key
    type = "S"
  }

  server_side_encryption {
    enabled = true
  }
}
