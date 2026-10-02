# Sorties du module network, conformes au contrat d'interface. Ce sont les seules
# informations que les modules compute et data connaissent du réseau.

output "vpc_id" {
  description = "VPC de l'environnement (Target Group du module compute)"
  value       = aws_vpc.main.id
}

output "public_subnet_ids" {
  description = "Subnets publics : ALB et bastion"
  value       = aws_subnet.public[*].id
}

output "app_subnet_ids" {
  description = "Subnets applicatifs : instances de l'ASG"
  value       = aws_subnet.app[*].id
}

output "data_subnet_ids" {
  description = "Subnets de données : groupe de sous-réseaux RDS"
  value       = aws_subnet.data[*].id
}

output "alb_sg_id" {
  description = "Security Group de l'ALB"
  value       = aws_security_group.alb.id
}

output "bastion_sg_id" {
  description = "Security Group du bastion"
  value       = aws_security_group.bastion.id
}

output "app_sg_id" {
  description = "Security Group des instances applicatives"
  value       = aws_security_group.app.id
}

output "rds_sg_id" {
  description = "Security Group de RDS"
  value       = aws_security_group.rds.id
}
