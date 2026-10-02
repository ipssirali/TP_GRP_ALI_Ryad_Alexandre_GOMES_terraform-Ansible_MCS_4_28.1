# Contrat d'interface entre modules

Ce document fixe ce que chaque module Terraform attend en entrée et expose en sortie, et les conventions communes. Il permet à chacun de travailler en parallèle sur son module sans attendre les autres : tant que l'interface est respectée, les modules s'assemblent.

Toute modification de ce contrat passe par une Pull Request relue par les deux membres, car elle impacte le code de l'autre.

## 1. Conventions communes

| Sujet | Règle |
|---|---|
| Projet | `trackfleet` (variable `project`) |
| Environnement | `staging` ou `prod` (variable `environment`) |
| Préfixe de nommage | `${project}-${environment}`, par exemple `trackfleet-prod-alb` |
| Tags sur toutes les ressources | `Project`, `Environment`, `ManagedBy = "terraform"` |
| Tags des instances de l'ASG | `Project`, `Environment`, `Role = "app"` (propagés au lancement) |
| Tag du bastion | `Role = "bastion"` |
| Région | `us-east-1`, jamais une autre |
| Valeur figée dans un module | **interdite** : tout ce qui varie entre staging et prod est une variable d'entrée |
| Secrets | jamais dans un `.tf` : variable `sensitive = true`, valeur dans un `.tfvars` non versionné |
| Commentaires | chaque bloc explique son rôle (le pourquoi), pas le nom de la ressource |

## 2. Module `network`

Contient le VPC, les subnets, l'Internet Gateway, la NAT Gateway, les tables de routage, l'endpoint S3 et les Security Groups.

**Entrées**

| Variable | Type | Rôle |
|---|---|---|
| `project` | string | préfixe de nommage |
| `environment` | string | `staging` ou `prod` |
| `vpc_cidr` | string | bloc du VPC |
| `public_subnet_cidrs` | list(string), 2 éléments | subnets publics (ALB, NAT, bastion) |
| `app_subnet_cidrs` | list(string), 2 éléments | subnets applicatifs (ASG) |
| `data_subnet_cidrs` | list(string), 2 éléments | subnets de données (RDS) |
| `admin_cidr` | string | IP d'administration en `/32` (SSH du bastion) |

**Sorties**

| Sortie | Consommée par |
|---|---|
| `vpc_id` | compute |
| `public_subnet_ids` | compute (ALB, bastion) |
| `app_subnet_ids` | compute (ASG) |
| `data_subnet_ids` | data (groupe de sous-réseaux RDS) |
| `alb_sg_id` | compute |
| `bastion_sg_id` | compute |
| `app_sg_id` | compute |
| `rds_sg_id` | data |

## 3. Module `compute`

Contient le bastion, l'ALB, le Target Group, le listener, le Launch Template et l'Auto Scaling Group.

**Entrées**

| Variable | Type | Rôle |
|---|---|---|
| `project`, `environment` | string | nommage et tags |
| `vpc_id` | string | sortie de `network` |
| `public_subnet_ids` | list(string) | sortie de `network` |
| `app_subnet_ids` | list(string) | sortie de `network` |
| `alb_sg_id`, `bastion_sg_id`, `app_sg_id` | string | sorties de `network` |
| `instance_type` | string | taille des instances |
| `key_name` | string | paire de clés SSH existante |
| `instance_profile_name` | string | profil déjà présent dans le compte |
| `asg_min_size`, `asg_desired_capacity`, `asg_max_size` | number | capacité de l'ASG |
| `health_check_path` | string | chemin du health check (`/health`) |

**Sorties**

| Sortie | Usage |
|---|---|
| `alb_dns_name` | tester le service |
| `asg_name` | consultation, diagnostic |
| `bastion_public_ip` | accès d'administration |

## 4. Module `data`

Contient le groupe de sous-réseaux RDS, l'instance RDS et le bucket S3.

**Entrées**

| Variable | Type | Rôle |
|---|---|---|
| `project`, `environment` | string | nommage et tags |
| `data_subnet_ids` | list(string) | sortie de `network` |
| `rds_sg_id` | string | sortie de `network` |
| `db_instance_class` | string | classe de l'instance RDS |
| `db_engine_version` | string | version de PostgreSQL |
| `db_name`, `db_username` | string | base et compte administrateur |
| `db_password` | string, **sensitive**, sans défaut | mot de passe administrateur |

**Sorties**

| Sortie | Usage |
|---|---|
| `rds_address` | passée à Ansible |
| `db_name`, `db_username` | passées à Ansible |
| `bucket_name` | nom du bucket de sauvegardes |

## 5. Environnements

Chaque environnement vit dans `terraform/environments/<env>/`, avec son propre state local et son propre `.tfvars`. Il appelle **les mêmes trois modules** et ne contient aucune ressource à lui.

| Paramètre | staging | prod |
|---|---|---|
| `vpc_cidr` | `10.20.0.0/16` | `10.10.0.0/16` |
| ASG min / désirée / max | 1 / 1 / 2 | 2 / 2 / 4 |
| `db_instance_class` | `db.t3.micro` | `db.t3.micro` |
| Environnement jetable | oui | non |

Les deux plages d'adresses ne se chevauchent pas, ce qui laisse la possibilité de les relier plus tard.

## 6. Ansible

| Sujet | Règle |
|---|---|
| Rôles | `webserver` et `monitoring` |
| Inventaire | plugin `amazon.aws.aws_ec2`, filtré sur `Project=trackfleet` |
| Groupes | un groupe par valeur du tag `Environment` (`staging`, `prod`) et un par `Role` |
| Variables | `group_vars/staging.yml` et `group_vars/prod.yml` |
| Secrets | `vault.yml` chiffré avec Ansible Vault, mot de passe du coffre hors du dépôt |

## 7. Qui fait quoi

| Membre | Périmètre | Environnement déployé |
|---|---|---|
| Membre 1 (`TitanHolo45`) | modules `network` et `data`, rôle `monitoring`, schéma | staging |
| Membre 2 (`ipssirali`) | module `compute`, rôle `webserver`, inventaire, `group_vars`, partie « workflow Git » du rapport | prod |

Chacun relit toutes les Pull Requests de l'autre avant tout merge.

## 8. Workflow Git

- La branche `main` est protégée : pas de push direct, une Pull Request et une approbation sont obligatoires.
- Une branche par fonctionnalité, nommée `<prénom>/<sujet>`, par exemple `ryad/module-compute`.
- Messages de commit au format `type(scope): description`, avec `feat`, `fix`, `chore`, `docs`, `refactor`.
- Une Pull Request contient un titre clair et une description de ce qui change et pourquoi. Elle n'est mergée qu'après une relecture qui comporte au moins un commentaire substantiel.
- Aucune branche ni Pull Request n'est supprimée après le merge.
