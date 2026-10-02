# Module data : couche de données d'un environnement. Il crée la base RDS
# PostgreSQL dans les subnets de données et le bucket S3 des sauvegardes. Il ne
# crée aucun élément réseau : subnets et Security Group viennent du module
# network.
terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    # Sert uniquement à générer un suffixe unique pour le nom du bucket.
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

locals {
  name_prefix = "${var.project}-${var.environment}"

  tags = {
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

# --- Base de données ---------------------------------------------------------------

# Limite RDS aux subnets de données, qui n'ont aucune route vers Internet.
resource "aws_db_subnet_group" "main" {
  name       = "${local.name_prefix}-db-subnets"
  subnet_ids = var.data_subnet_ids

  tags = merge(local.tags, { Name = "${local.name_prefix}-db-subnets" })
}

# Base PostgreSQL managée : AWS gère les correctifs et les sauvegardes
# automatiques. La classe et la version arrivent de l'environnement.
resource "aws_db_instance" "main" {
  identifier     = "${local.name_prefix}-db"
  engine         = "postgres"
  engine_version = var.db_engine_version
  instance_class = var.db_instance_class

  allocated_storage = 20
  storage_type      = "gp3"
  # Chiffrement au repos des données et des snapshots.
  storage_encrypted = true

  db_name  = var.db_name
  username = var.db_username
  # Le secret arrive d'une variable sensible et n'est écrit dans aucun fichier
  # versionné. Il reste présent dans le state, qui n'est donc jamais commité.
  password = var.db_password

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [var.rds_sg_id]
  # Aucune adresse publique : la base n'est joignable que depuis le VPC.
  publicly_accessible = false

  # Une seule zone pour rester dans les quotas du compte académique, en staging
  # comme en prod. Sur un vrai compte, la prod passerait en multi_az.
  multi_az = false

  # Sauvegarde quotidienne conservée un jour : le minimum utile ici.
  backup_retention_period = 1

  # Environnements de TP : destruction rapide, sans snapshot final ni
  # protection contre la suppression.
  skip_final_snapshot = true
  deletion_protection = false
  apply_immediately   = true

  tags = merge(local.tags, { Name = "${local.name_prefix}-db" })
}

# --- Stockage des sauvegardes -------------------------------------------------------

# Les noms de bucket sont uniques au niveau mondial : un suffixe aléatoire évite
# un échec si le nom est déjà pris par un autre compte.
resource "random_id" "bucket_suffix" {
  byte_length = 4
}

resource "aws_s3_bucket" "backups" {
  bucket = "${local.name_prefix}-backups-${random_id.bucket_suffix.hex}"

  # Permet à destroy de vider le bucket, versions comprises : les deux
  # environnements de TP sont détruits en fin de séance.
  force_destroy = true

  tags = merge(local.tags, { Name = "${local.name_prefix}-backups" })
}

# Un fichier écrasé ou supprimé par erreur reste récupérable.
resource "aws_s3_bucket_versioning" "backups" {
  bucket = aws_s3_bucket.backups.id

  versioning_configuration {
    status = "Enabled"
  }
}

# Tout objet déposé est chiffré, même si le client ne le demande pas.
resource "aws_s3_bucket_server_side_encryption_configuration" "backups" {
  bucket = aws_s3_bucket.backups.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Aucune exposition publique possible, même si une ACL ou une policy publique
# était ajoutée par erreur plus tard.
resource "aws_s3_bucket_public_access_block" "backups" {
  bucket = aws_s3_bucket.backups.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ACL désactivées : les droits ne passent que par IAM et la policy du bucket,
# un seul endroit à auditer.
resource "aws_s3_bucket_ownership_controls" "backups" {
  bucket = aws_s3_bucket.backups.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

# Rétention : les anciennes versions disparaissent après 30 jours, pour que le
# versioning ne fasse pas grossir le stockage sans fin.
resource "aws_s3_bucket_lifecycle_configuration" "backups" {
  bucket = aws_s3_bucket.backups.id

  rule {
    id     = "retention-anciennes-versions"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = 30
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }

  depends_on = [aws_s3_bucket_versioning.backups]
}

# Refuse tout accès en clair (HTTP) ou avec un TLS antérieur à 1.2, quel que
# soit l'appelant.
data "aws_iam_policy_document" "backups" {
  statement {
    sid       = "DenyInsecureTransport"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [aws_s3_bucket.backups.arn, "${aws_s3_bucket.backups.arn}/*"]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }

  statement {
    sid       = "DenyOutdatedTLS"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [aws_s3_bucket.backups.arn, "${aws_s3_bucket.backups.arn}/*"]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    condition {
      test     = "NumericLessThan"
      variable = "s3:TlsVersion"
      values   = ["1.2"]
    }
  }
}

# Appliquée après le blocage d'accès public, sinon AWS peut la refuser.
resource "aws_s3_bucket_policy" "backups" {
  bucket = aws_s3_bucket.backups.id
  policy = data.aws_iam_policy_document.backups.json

  depends_on = [aws_s3_bucket_public_access_block.backups]
}
