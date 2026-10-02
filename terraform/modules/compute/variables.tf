# Interface d'entrée du module compute. Aucune valeur propre à un environnement
# n'est écrite dans le module : tout ce qui change entre staging et prod arrive
# par ces variables, fournies par le dossier d'environnement qui l'appelle.

# --- Identité et nommage -------------------------------------------------------

variable "project" {
  description = "Nom du projet : préfixe des ressources et valeur du tag Project"
  type        = string
}

# Contrôlé à l'entrée : une faute de frappe sur l'environnement fausserait les
# noms, les tags et donc le ciblage de l'inventaire Ansible.
variable "environment" {
  description = "Environnement déployé : staging ou prod"
  type        = string

  validation {
    condition     = contains(["staging", "prod"], var.environment)
    error_message = "environment doit valoir \"staging\" ou \"prod\"."
  }
}

# --- Réseau (sorties du module network) ---------------------------------------

variable "vpc_id" {
  description = "VPC dans lequel est créé le Target Group"
  type        = string
}

variable "public_subnet_ids" {
  description = "Subnets publics : l'ALB s'y répartit, le bastion est dans le premier"
  type        = list(string)
}

variable "app_subnet_ids" {
  description = "Subnets privés applicatifs : l'ASG y lance ses instances"
  type        = list(string)
}

variable "alb_sg_id" {
  description = "Security Group de l'ALB"
  type        = string
}

variable "bastion_sg_id" {
  description = "Security Group du bastion"
  type        = string
}

variable "app_sg_id" {
  description = "Security Group des instances applicatives"
  type        = string
}

# --- Instances -------------------------------------------------------------------

variable "instance_type" {
  description = "Taille des instances (bastion et ASG)"
  type        = string
}

variable "key_name" {
  description = "Paire de clés SSH déjà importée dans AWS"
  type        = string
}

variable "instance_profile_name" {
  description = "Instance profile déjà présent dans le compte : donne accès à S3 sans créer de ressource IAM"
  type        = string
}

# --- Capacité de l'Auto Scaling Group ------------------------------------------

variable "asg_min_size" {
  description = "Nombre minimal d'instances : plancher de l'ASG"
  type        = number
}

variable "asg_desired_capacity" {
  description = "Nombre d'instances voulu en temps normal"
  type        = number
}

variable "asg_max_size" {
  description = "Nombre maximal d'instances : plafond de l'ASG"
  type        = number
}

# --- Health check ----------------------------------------------------------------

# Exposé car le chemin doit correspondre à celui que sert le rôle Ansible du
# serveur web : les deux doivent changer ensemble.
variable "health_check_path" {
  description = "Chemin interrogé par l'ALB pour juger une instance saine"
  type        = string
  default     = "/health"
}
