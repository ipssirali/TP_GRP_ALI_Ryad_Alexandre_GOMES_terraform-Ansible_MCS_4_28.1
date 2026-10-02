# Module compute : couche applicative d'un environnement. Il crée le bastion
# d'administration, la répartition de charge (ALB, Target Group, listener) et
# les instances (Launch Template, Auto Scaling Group). Il ne crée ni réseau ni
# Security Group : il consomme ceux du module network, ce qui garde chaque
# module responsable d'un seul périmètre.
terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

locals {
  # Le nom de l'environnement figure dans chaque ressource : staging et prod
  # peuvent ainsi coexister dans un même compte sans collision de noms.
  name_prefix = "${var.project}-${var.environment}"

  # Tags posés explicitement sur les ressources du module, en plus de ceux du
  # provider : le module reste correctement étiqueté même s'il est appelé depuis
  # un environnement qui n'en définit pas.
  tags = {
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

# AMI résolue dynamiquement chez Canonical : un identifiant d'AMI écrit en dur
# changerait d'une région à l'autre et deviendrait obsolète avec les mises à jour.
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# Bastion : unique porte d'entrée d'administration. Il est dans un subnet public
# avec une IP publique, mais son Security Group (fourni par network) ne laisse
# passer que l'IP de l'administrateur. Le tag Role permet à l'inventaire Ansible
# de le retrouver pour le rebond SSH.
resource "aws_instance" "bastion" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.instance_type
  subnet_id                   = var.public_subnet_ids[0]
  vpc_security_group_ids      = [var.bastion_sg_id]
  key_name                    = var.key_name
  associate_public_ip_address = true

  # IMDSv2 obligatoire : empêche qu'une faille SSRF lise les métadonnées.
  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-bastion"
    Role = "bastion"
  })
}

# --- Répartition de charge -----------------------------------------------------

# Cible de l'ALB. Le health check interroge un chemin dédié plutôt que la page
# d'accueil : il ne dépend ni de PHP ni de la base, donc une panne de RDS ne
# fait pas retirer toutes les instances du service. Intervalle de 15 s et 2
# succès pour déclarer une instance saine en 30 s ; 3 échecs (45 s) avant de la
# retirer, pour ne pas réagir à un incident très bref.
resource "aws_lb_target_group" "app" {
  name     = "${local.name_prefix}-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = var.vpc_id

  # Une désinscription rapide accélère les remplacements d'instance et le destroy.
  deregistration_delay = 30

  health_check {
    path                = var.health_check_path
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 15
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  tags = merge(local.tags, { Name = "${local.name_prefix}-tg" })
}

# ALB public réparti sur les subnets publics : point d'entrée unique du trafic
# web, il survit à la perte d'une zone. L'appelant doit déclarer
# depends_on = [module.network] sur ce module, pour que la passerelle Internet
# existe avant que l'ALB tente de s'exposer.
resource "aws_lb" "app" {
  name               = "${local.name_prefix}-alb"
  load_balancer_type = "application"
  internal           = false
  security_groups    = [var.alb_sg_id]
  subnets            = var.public_subnet_ids

  tags = merge(local.tags, { Name = "${local.name_prefix}-alb" })
}

# Le listener fait le lien entre le port exposé par l'ALB et le Target Group.
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.app.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }

  tags = local.tags
}
