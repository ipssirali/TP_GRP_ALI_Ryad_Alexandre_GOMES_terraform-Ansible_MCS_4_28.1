# Sorties du module data, conformes au contrat d'interface. Le mot de passe n'en
# fait jamais partie : côté Ansible, il vient du coffre de chaque environnement.

output "rds_address" {
  description = "Nom d'hôte de RDS, sans le port, passé à Ansible"
  value       = aws_db_instance.main.address
}

output "db_name" {
  description = "Nom de la base applicative"
  value       = aws_db_instance.main.db_name
}

output "db_username" {
  description = "Compte administrateur de la base"
  value       = aws_db_instance.main.username
}

output "bucket_name" {
  description = "Nom du bucket S3 de sauvegardes"
  value       = aws_s3_bucket.backups.bucket
}
