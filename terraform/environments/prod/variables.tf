# Variables d'entrée de l'environnement. Ce fichier est identique pour tous les
# environnements : ce qui les distingue, ce sont uniquement les valeurs
# fournies par <environnement>.tfvars. Aucune valeur propre à un environnement
# n'est écrite ici, ni dans main.tf.

# --- Identité --------------------------------------------------------------------

variable "region" {
  description = "Région AWS unique du projet"
  type        = string
  default     = "us-east-1"
}

variable "project" {
  description = "Nom du projet : préfixe des ressources et valeur du tag Project"
  type        = string
  default     = "trackfleet"
}

# Pas de valeur par défaut : c'est le fichier .tfvars qui désigne l'environnement,
# ce qui évite de déployer par erreur avec le mauvais nom.
variable "environment" {
  description = "Environnement déployé : staging ou prod"
  type        = string

  validation {
    condition     = contains(["staging", "prod"], var.environment)
    error_message = "environment doit valoir \"staging\" ou \"prod\"."
  }
}

# --- Réseau ------------------------------------------------------------------------

variable "vpc_cidr" {
  description = "Bloc du VPC de l'environnement"
  type        = string
}

variable "public_subnet_cidrs" {
  description = "Subnets publics (ALB, NAT, bastion), un par zone"
  type        = list(string)
}

variable "app_subnet_cidrs" {
  description = "Subnets privés applicatifs (ASG), un par zone"
  type        = list(string)
}

variable "data_subnet_cidrs" {
  description = "Subnets privés de données (RDS), un par zone"
  type        = list(string)
}

variable "admin_cidr" {
  description = "IP d'administration en /32 : seule source autorisée sur le SSH du bastion"
  type        = string
}

# --- Calcul ------------------------------------------------------------------------

variable "instance_type" {
  description = "Taille des instances (bastion et ASG)"
  type        = string
}

variable "key_name" {
  description = "Paire de clés SSH déjà importée dans AWS"
  type        = string
}

variable "instance_profile_name" {
  description = "Instance profile déjà présent dans le compte"
  type        = string
}

variable "asg_min_size" {
  description = "Nombre minimal d'instances"
  type        = number
}

variable "asg_desired_capacity" {
  description = "Nombre d'instances voulu en temps normal"
  type        = number
}

variable "asg_max_size" {
  description = "Nombre maximal d'instances"
  type        = number
}

# --- Données -------------------------------------------------------------------------

variable "db_instance_class" {
  description = "Classe de l'instance RDS"
  type        = string
}

variable "db_engine_version" {
  description = "Version de PostgreSQL"
  type        = string
}

variable "db_name" {
  description = "Nom de la base applicative"
  type        = string
}

variable "db_username" {
  description = "Compte administrateur de la base"
  type        = string
}

# Aucune valeur par défaut volontairement : le mot de passe ne doit exister dans
# aucun fichier .tf. sensitive = true le masque dans le plan, les sorties et les
# journaux. Sa valeur est dans <environnement>.tfvars, ignoré par git.
variable "db_password" {
  description = "Mot de passe administrateur RDS, fourni par le .tfvars de l'environnement (non versionné)"
  type        = string
  sensitive   = true
}
