# Sorties de l'environnement : ce dont on a besoin pour tester le service et pour
# lancer Ansible (le script de lancement les lit avec terraform output -raw).
# Aucune ne contient de secret.

output "alb_dns_name" {
  description = "Nom DNS public de l'ALB, à utiliser pour tester le service"
  value       = module.compute.alb_dns_name
}

output "bastion_public_ip" {
  description = "IP publique du bastion, point d'entrée d'administration"
  value       = module.compute.bastion_public_ip
}

output "asg_name" {
  description = "Nom de l'Auto Scaling Group"
  value       = module.compute.asg_name
}

# Ansible a besoin de l'hôte de la base, du nom de la base et du compte ; le mot
# de passe n'est jamais exposé, il vit dans le coffre Ansible Vault.
output "rds_address" {
  description = "Nom d'hôte de RDS, sans le port"
  value       = module.data.rds_address
}

output "db_name" {
  description = "Nom de la base applicative"
  value       = module.data.db_name
}

output "db_username" {
  description = "Compte administrateur de la base"
  value       = module.data.db_username
}

output "bucket_name" {
  description = "Nom du bucket S3 de sauvegardes"
  value       = module.data.bucket_name
}
