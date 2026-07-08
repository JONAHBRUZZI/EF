################################################################################
# ECR Private Repositories (one per service)
################################################################################
resource "aws_ecr_repository" "this" {
  for_each = toset(var.apps_repository)

  name                 = "${local.name_prefix}-${each.key}-repo"
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = {
    Name = "${local.name_prefix}-${each.key}-repo"
  }
}

resource "aws_ecr_lifecycle_policy" "this" {
  for_each = toset(var.apps_repository)

  repository = aws_ecr_repository.this[each.key].name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Remove untagged images after 7 days"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 7
        }
        action = {
          type = "expire"
        }
      },
      {
        # El pipeline etiqueta las imagenes con el SHA del commit y "latest" (no con
        # prefijo "v"), asi que la regla usa tagStatus "any" para cubrir todas las
        # imagenes restantes y evitar que se acumulen indefinidamente en ECR.
        rulePriority = 2
        description  = "Keep last 10 images"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = 10
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}
