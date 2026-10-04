resource "aws_ecr_repository" "this" {
  for_each = var.repositories

  name = "${var.namespace}/${each.key}"

  # Tags v1.0.0-<sha> nunca são sobrescritas: o que o GitOps aponta é exatamente o que foi escaneado.
  image_tag_mutability = "IMMUTABLE"

  # Permite terraform destroy mesmo com imagens no repositório.
  force_delete = true

  image_scanning_configuration {
    scan_on_push = true
  }
}

resource "aws_ecr_lifecycle_policy" "this" {
  for_each = aws_ecr_repository.this

  repository = each.value.name
  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Mantém as ${var.max_images} imagens mais recentes"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = var.max_images
      }
      action = { type = "expire" }
    }]
  })
}
