# Sorties du module compute, conformes au contrat d'interface. Aucune ne contient
# de secret.

output "alb_dns_name" {
  description = "Nom DNS public de l'ALB, à utiliser pour tester le service"
  value       = aws_lb.app.dns_name
}

# Utile pour consulter l'historique et l'état de l'ASG sans connaître son nom
# construit par le module.
output "asg_name" {
  description = "Nom de l'Auto Scaling Group"
  value       = aws_autoscaling_group.app.name
}

output "bastion_public_ip" {
  description = "IP publique du bastion, point d'entrée d'administration"
  value       = aws_instance.bastion.public_ip
}
