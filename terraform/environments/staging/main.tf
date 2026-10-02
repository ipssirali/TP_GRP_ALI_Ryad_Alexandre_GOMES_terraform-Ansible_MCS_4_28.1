# Environnement : assemble les trois modules (network, compute, data) avec les
# valeurs de <environnement>.tfvars. Il ne définit aucune ressource lui-même et
# ne contient aucune valeur propre à un environnement : ce fichier est
# strictement identique pour staging et prod. Chaque dossier garde son propre
# state local, donc une opération sur l'un n'affecte jamais l'autre.
terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# default_tags pose Project, Environment et ManagedBy sur les ressources créées
# directement : un auditeur sait d'où vient chaque ressource et dans quel
# environnement elle vit. Les modules posent aussi ces tags explicitement.
provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project     = var.project
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}

# Réseau : fondation de l'environnement. Les autres modules consomment ses
# sorties (identifiants de VPC, de subnets et de Security Groups).
module "network" {
  source = "../../modules/network"

  project             = var.project
  environment         = var.environment
  vpc_cidr            = var.vpc_cidr
  public_subnet_cidrs = var.public_subnet_cidrs
  app_subnet_cidrs    = var.app_subnet_cidrs
  data_subnet_cidrs   = var.data_subnet_cidrs
  admin_cidr          = var.admin_cidr
}

# Couche applicative : bastion, ALB, Launch Template et ASG. Le depends_on sur
# network garantit que la NAT et les routes sont entièrement créées avant le
# premier démarrage des instances, qui installent leurs paquets au boot : sans
# lui, les sorties du module (subnets, groupes) existeraient avant les routes.
module "compute" {
  source = "../../modules/compute"

  project               = var.project
  environment           = var.environment
  vpc_id                = module.network.vpc_id
  public_subnet_ids     = module.network.public_subnet_ids
  app_subnet_ids        = module.network.app_subnet_ids
  alb_sg_id             = module.network.alb_sg_id
  bastion_sg_id         = module.network.bastion_sg_id
  app_sg_id             = module.network.app_sg_id
  instance_type         = var.instance_type
  key_name              = var.key_name
  instance_profile_name = var.instance_profile_name
  asg_min_size          = var.asg_min_size
  asg_desired_capacity  = var.asg_desired_capacity
  asg_max_size          = var.asg_max_size

  depends_on = [module.network]
}

# Données : base RDS privée et bucket S3. Le mot de passe traverse l'environnement
# sans jamais être écrit : il arrive de la variable sensible et repart vers le module.
module "data" {
  source = "../../modules/data"

  project           = var.project
  environment       = var.environment
  data_subnet_ids   = module.network.data_subnet_ids
  rds_sg_id         = module.network.rds_sg_id
  db_instance_class = var.db_instance_class
  db_engine_version = var.db_engine_version
  db_name           = var.db_name
  db_username       = var.db_username
  db_password       = var.db_password
}
