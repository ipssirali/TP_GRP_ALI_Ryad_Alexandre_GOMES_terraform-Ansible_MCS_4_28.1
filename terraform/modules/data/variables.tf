# Interface d'entrée du module data, conforme au contrat d'interface. Aucune
# valeur propre à un environnement n'est écrite dans le module.

# --- Identité et nommage -------------------------------------------------------

variable "project" {
  description = "Nom du projet : préfixe des ressources et valeur du tag Project"
  type        = string
}

variable "environment" {
  description = "Environnement déployé : staging ou prod"
  type        = string

  validation {
    condition     = contains(["staging", "prod"], var.environment)
    error_message = "environment doit valoir \"staging\" ou \"prod\"."
  }
}

# --- Réseau (sorties du module network) ---------------------------------------

# RDS exige des subnets dans au moins deux zones, même sans réplica.
variable "data_subnet_ids" {
  description = "Subnets de données : groupe de sous-réseaux RDS"
  type        = list(string)

  validation {
    condition     = length(var.data_subnet_ids) >= 2
    error_message = "RDS exige au moins 2 subnets, dans deux zones différentes."
  }
}

variable "rds_sg_id" {
  description = "Security Group de RDS"
  type        = string
}

# --- Base de données ---------------------------------------------------------------

variable "db_instance_class" {
  description = "Classe de l'instance RDS, par exemple db.t3.micro"
  type        = string
}

variable "db_engine_version" {
  description = "Version de PostgreSQL"
  type        = string
}

# PostgreSQL impose un nom qui commence par une lettre, avec seulement des
# lettres, chiffres et underscores.
variable "db_name" {
  description = "Nom de la base applicative"
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z][A-Za-z0-9_]{0,62}$", var.db_name))
    error_message = "db_name : une lettre puis lettres, chiffres ou _, 63 caractères maximum."
  }
}

variable "db_username" {
  description = "Compte administrateur de la base"
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z][A-Za-z0-9_]{0,62}$", var.db_username))
    error_message = "db_username : une lettre puis lettres, chiffres ou _, 63 caractères maximum."
  }
}

# Aucune valeur par défaut : le mot de passe n'existe dans aucun fichier .tf.
# La validation reprend les règles de RDS (8 caractères minimum, sans / @ " ni
# espace) pour échouer dès le plan plutôt qu'au bout de plusieurs minutes d'apply.
variable "db_password" {
  description = "Mot de passe administrateur RDS"
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.db_password) >= 8 && !can(regex("[/@\" ]", var.db_password))
    error_message = "db_password : 8 caractères minimum, sans / @ \" ni espace."
  }
}
