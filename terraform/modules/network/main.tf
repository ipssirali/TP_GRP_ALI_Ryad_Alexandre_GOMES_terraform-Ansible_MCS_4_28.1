# Module network : fondation réseau d'un environnement. Il crée le VPC, les
# trois couches de subnets sur deux zones, la sortie Internet (IGW et NAT), le
# routage, l'endpoint S3 et les quatre Security Groups. Les autres modules ne
# créent aucun élément réseau : ils consomment les sorties de celui-ci.
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
  # peuvent coexister dans un même compte sans collision de noms.
  name_prefix = "${var.project}-${var.environment}"

  # Tags posés explicitement, en plus de ceux du provider : le module reste
  # correctement étiqueté quel que soit l'environnement qui l'appelle.
  tags = {
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "terraform"
  }

  # Les deux premières zones disponibles de la région, lues dynamiquement
  # plutôt qu'écrites en dur.
  azs = slice(data.aws_availability_zones.available.names, 0, 2)

  # Port de PostgreSQL. Ce n'est pas une valeur d'environnement (staging et prod
  # utilisent le même moteur) : il est donc fixé ici, en un seul endroit.
  db_port = 5432
}

data "aws_availability_zones" "available" {
  state = "available"
}

# Région courante, utilisée pour construire le nom du service de l'endpoint S3.
data "aws_region" "current" {}

# --- VPC et sortie Internet ----------------------------------------------------

# Réseau isolé de l'environnement. Les noms DNS sont activés pour que les
# instances résolvent l'adresse de RDS.
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(local.tags, { Name = "${local.name_prefix}-vpc" })
}

# Unique porte vers Internet, utilisée seulement par la couche publique.
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = merge(local.tags, { Name = "${local.name_prefix}-igw" })
}

# --- Subnets ---------------------------------------------------------------------

# Couche publique : seule couche où une IP publique est attribuée au lancement.
resource "aws_subnet" "public" {
  count = length(var.public_subnet_cidrs)

  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = local.azs[count.index]
  map_public_ip_on_launch = true

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-public-${local.azs[count.index]}"
    Tier = "public"
  })
}

# Couche applicative : aucune IP publique, les instances ne sont joignables que
# par l'ALB (web) et le bastion (administration).
resource "aws_subnet" "app" {
  count = length(var.app_subnet_cidrs)

  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.app_subnet_cidrs[count.index]
  availability_zone       = local.azs[count.index]
  map_public_ip_on_launch = false

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-app-${local.azs[count.index]}"
    Tier = "app"
  })
}

# Couche données : réservée à RDS, sans aucune route vers Internet.
resource "aws_subnet" "data" {
  count = length(var.data_subnet_cidrs)

  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.data_subnet_cidrs[count.index]
  availability_zone       = local.azs[count.index]
  map_public_ip_on_launch = false

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-data-${local.azs[count.index]}"
    Tier = "data"
  })
}

# --- NAT ---------------------------------------------------------------------------

# IP publique fixe portée par la NAT.
resource "aws_eip" "nat" {
  domain = "vpc"

  tags = merge(local.tags, { Name = "${local.name_prefix}-nat-eip" })

  depends_on = [aws_internet_gateway.main]
}

# Permet aux instances applicatives d'installer leurs paquets sans être
# joignables depuis Internet. Une seule NAT, dans la première zone, pour limiter
# le coût sur un compte académique : si cette zone tombe, seul l'accès sortant
# est perdu, le site continue de répondre. En production réelle, on en mettrait
# une par zone.
resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id

  tags = merge(local.tags, { Name = "${local.name_prefix}-nat" })

  depends_on = [aws_internet_gateway.main]
}

# --- Routage -----------------------------------------------------------------------

# Une table par couche : chaque couche n'a que les routes dont elle a besoin.

# Couche publique : route par défaut vers l'Internet Gateway.
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = merge(local.tags, { Name = "${local.name_prefix}-rt-public" })
}

resource "aws_route_table_association" "public" {
  count = length(aws_subnet.public)

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# Couche applicative : sortie uniquement par la NAT, donc seulement pour du
# trafic initié depuis l'intérieur.
resource "aws_route_table" "app" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main.id
  }

  tags = merge(local.tags, { Name = "${local.name_prefix}-rt-app" })
}

resource "aws_route_table_association" "app" {
  count = length(aws_subnet.app)

  subnet_id      = aws_subnet.app[count.index].id
  route_table_id = aws_route_table.app.id
}

# Couche données : table explicite sans route par défaut, seule la route locale
# du VPC existe. On ne s'appuie pas sur la table principale du VPC, qui pourrait
# recevoir une route par erreur : une base compromise ne peut rien envoyer vers
# Internet.
resource "aws_route_table" "data" {
  vpc_id = aws_vpc.main.id

  tags = merge(local.tags, { Name = "${local.name_prefix}-rt-data" })
}

resource "aws_route_table_association" "data" {
  count = length(aws_subnet.data)

  subnet_id      = aws_subnet.data[count.index].id
  route_table_id = aws_route_table.data.id
}

# --- Endpoint S3 ---------------------------------------------------------------------

# Endpoint de type Gateway : le trafic des instances vers S3 (sauvegardes) reste
# sur le réseau AWS au lieu de passer par la NAT. C'est gratuit, alors que la
# NAT facture chaque Go qui la traverse.
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${data.aws_region.current.name}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.app.id]

  tags = merge(local.tags, { Name = "${local.name_prefix}-s3-endpoint" })
}

# --- Security Groups ---------------------------------------------------------------

# Chaîne de confiance : Internet -> ALB -> app -> RDS. Chaque groupe interne
# n'accepte que le groupe juste en amont, jamais une plage d'adresses : une
# instance reste injoignable même si son IP privée est connue.
# Les règles sont des ressources séparées pour éviter les dépendances
# circulaires entre groupes qui se référencent l'un l'autre.
# Les descriptions restent en ASCII sans apostrophe : AWS refuse les autres
# caractères dans ce champ.

resource "aws_security_group" "alb" {
  name        = "${local.name_prefix}-sg-alb"
  description = "Point entree public - HTTP depuis Internet"
  vpc_id      = aws_vpc.main.id

  tags = merge(local.tags, { Name = "${local.name_prefix}-sg-alb" })
}

resource "aws_security_group" "bastion" {
  name        = "${local.name_prefix}-sg-bastion"
  description = "SSH administration depuis IP admin uniquement"
  vpc_id      = aws_vpc.main.id

  tags = merge(local.tags, { Name = "${local.name_prefix}-sg-bastion" })
}

resource "aws_security_group" "app" {
  name        = "${local.name_prefix}-sg-app"
  description = "Instances applicatives - HTTP depuis ALB et SSH depuis bastion"
  vpc_id      = aws_vpc.main.id

  tags = merge(local.tags, { Name = "${local.name_prefix}-sg-app" })
}

resource "aws_security_group" "rds" {
  name        = "${local.name_prefix}-sg-rds"
  description = "PostgreSQL depuis la couche applicative uniquement"
  vpc_id      = aws_vpc.main.id

  tags = merge(local.tags, { Name = "${local.name_prefix}-sg-rds" })
}

# ALB : seule règle ouverte à tout Internet de l'infrastructure, c'est le point
# d'entrée public voulu. Il ne peut ensuite parler qu'aux instances.
resource "aws_vpc_security_group_ingress_rule" "alb_http" {
  security_group_id = aws_security_group.alb.id
  description       = "HTTP public"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
}

resource "aws_vpc_security_group_egress_rule" "alb_to_app" {
  security_group_id            = aws_security_group.alb.id
  description                  = "Vers les instances applicatives"
  referenced_security_group_id = aws_security_group.app.id
  ip_protocol                  = "tcp"
  from_port                    = 80
  to_port                      = 80
}

# Bastion : SSH depuis la seule IP de l'administrateur, et rebond SSH vers les
# instances (c'est par là que passe Ansible).
resource "aws_vpc_security_group_ingress_rule" "bastion_ssh" {
  security_group_id = aws_security_group.bastion.id
  description       = "SSH depuis le poste admin"
  cidr_ipv4         = var.admin_cidr
  ip_protocol       = "tcp"
  from_port         = 22
  to_port           = 22
}

resource "aws_vpc_security_group_egress_rule" "bastion_to_app" {
  security_group_id            = aws_security_group.bastion.id
  description                  = "Rebond SSH vers la couche applicative"
  referenced_security_group_id = aws_security_group.app.id
  ip_protocol                  = "tcp"
  from_port                    = 22
  to_port                      = 22
}

# Instances : HTTP seulement depuis l'ALB (impossible de contourner le load
# balancer), SSH seulement depuis le bastion.
resource "aws_vpc_security_group_ingress_rule" "app_http_from_alb" {
  security_group_id            = aws_security_group.app.id
  description                  = "HTTP depuis ALB"
  referenced_security_group_id = aws_security_group.alb.id
  ip_protocol                  = "tcp"
  from_port                    = 80
  to_port                      = 80
}

resource "aws_vpc_security_group_ingress_rule" "app_ssh_from_bastion" {
  security_group_id            = aws_security_group.app.id
  description                  = "SSH depuis le bastion"
  referenced_security_group_id = aws_security_group.bastion.id
  ip_protocol                  = "tcp"
  from_port                    = 22
  to_port                      = 22
}

# Sorties des instances limitées au nécessaire : HTTP et HTTPS pour les dépôts
# de paquets (par la NAT) et S3 (par l'endpoint), PostgreSQL vers RDS.
resource "aws_vpc_security_group_egress_rule" "app_http_out" {
  security_group_id = aws_security_group.app.id
  description       = "Depots de paquets HTTP"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
}

resource "aws_vpc_security_group_egress_rule" "app_https_out" {
  security_group_id = aws_security_group.app.id
  description       = "Depots de paquets et S3 en HTTPS"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
}

resource "aws_vpc_security_group_egress_rule" "app_to_rds" {
  security_group_id            = aws_security_group.app.id
  description                  = "PostgreSQL vers RDS"
  referenced_security_group_id = aws_security_group.rds.id
  ip_protocol                  = "tcp"
  from_port                    = local.db_port
  to_port                      = local.db_port
}

# RDS : connexions acceptées uniquement depuis les instances applicatives. Ni
# l'ALB, ni le bastion, ni Internet ne peuvent joindre la base. Aucune règle de
# sortie : la base n'initie aucune connexion.
resource "aws_vpc_security_group_ingress_rule" "rds_from_app" {
  security_group_id            = aws_security_group.rds.id
  description                  = "PostgreSQL depuis la couche applicative"
  referenced_security_group_id = aws_security_group.app.id
  ip_protocol                  = "tcp"
  from_port                    = local.db_port
  to_port                      = local.db_port
}
