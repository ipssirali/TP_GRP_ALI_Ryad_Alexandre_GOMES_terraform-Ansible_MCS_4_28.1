# Interface d'entrée du module network, conforme au contrat d'interface. Aucune
# variable n'a de valeur par défaut : c'est l'environnement appelant qui fournit
# l'adressage, ce qui empêche qu'une valeur de prod reste cachée dans le module.

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

# --- Adressage -------------------------------------------------------------------

variable "vpc_cidr" {
  description = "Bloc du VPC de l'environnement"
  type        = string

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "vpc_cidr doit être un bloc CIDR valide, par exemple 10.10.0.0/16."
  }
}

# Deux sous-réseaux par couche, un par zone de disponibilité : c'est ce qui
# permet à l'ALB et à l'ASG de survivre à la perte d'une zone. On impose
# exactement deux éléments pour que les trois listes restent alignées sur les
# mêmes zones.
variable "public_subnet_cidrs" {
  description = "Subnets publics (ALB, NAT, bastion), un par zone"
  type        = list(string)

  validation {
    condition     = length(var.public_subnet_cidrs) == 2
    error_message = "public_subnet_cidrs doit contenir exactement 2 blocs (un par zone)."
  }
}

variable "app_subnet_cidrs" {
  description = "Subnets privés applicatifs (ASG), un par zone"
  type        = list(string)

  validation {
    condition     = length(var.app_subnet_cidrs) == 2
    error_message = "app_subnet_cidrs doit contenir exactement 2 blocs (un par zone)."
  }
}

variable "data_subnet_cidrs" {
  description = "Subnets privés de données (RDS), un par zone"
  type        = list(string)

  validation {
    condition     = length(var.data_subnet_cidrs) == 2
    error_message = "data_subnet_cidrs doit contenir exactement 2 blocs (un par zone)."
  }
}

# Une seule adresse autorisée sur le port SSH du bastion : on refuse dès le plan
# un bloc plus large, qui exposerait le port 22 à tout un réseau.
variable "admin_cidr" {
  description = "IP d'administration en /32 : seule source autorisée sur le SSH du bastion"
  type        = string

  validation {
    condition     = can(cidrhost(var.admin_cidr, 0)) && endswith(var.admin_cidr, "/32")
    error_message = "admin_cidr doit être une adresse unique au format x.x.x.x/32."
  }
}
