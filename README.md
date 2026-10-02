# NeoCargo Analytics - TrackFleet

Infrastructure multi-environnements (Terraform, Ansible).

Projet de groupe, Mastere Cybersecurite 4A.

## Objectif

Réorganiser l'infrastructure de TrackFleet en modules Terraform réutilisables et en rôles Ansible, pour déployer deux environnements (staging et prod) à partir du même code, en ne changeant que des variables. Le travail se fait en équipe sur ce dépôt, avec une branche `main` protégée et des Pull Requests relues.

## Arborescence

```
.
├── terraform/
│   ├── modules/
│   │   ├── network/      # VPC, subnets, routage, NAT, Security Groups
│   │   ├── compute/      # bastion, ALB, Target Group, Launch Template, ASG
│   │   └── data/         # RDS, S3, gestion du secret
│   └── environments/
│       ├── staging/      # appelle les trois modules, avec son .tfvars
│       └── prod/         # appelle les mêmes modules, avec un autre .tfvars
├── ansible/
│   ├── roles/
│   │   ├── webserver/    # serveur applicatif
│   │   └── monitoring/   # supervision basique
│   ├── inventory/        # inventaire dynamique aws_ec2
│   └── group_vars/       # variables par environnement
└── docs/                 # contrat d'interface, schéma, rapport
```

## Documentation

- [Contrat d'interface entre modules](docs/CONTRAT_INTERFACES.md) : variables, sorties, conventions, répartition des rôles et workflow Git.

## Règles de travail

- Pas de push direct sur `main` : toute modification passe par une Pull Request relue par l'autre membre.
- Une branche par fonctionnalité, nommée `<prénom>/<sujet>`.
- Commits au format `type(scope): description`.
- Aucun secret dans le dépôt : les `.tfvars` réels, les clés et les states sont ignorés par git.
