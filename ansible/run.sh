#!/usr/bin/env bash
# Lance le playbook sur UN environnement. L'hôte RDS, le nom de la base et le
# compte sont lus directement dans les sorties Terraform de cet environnement et
# passés à Ansible en extra-vars : rien n'est recopié à la main, rien n'est écrit
# sur disque. Le mot de passe de la base vient du coffre de l'environnement.
#
# Usage : ./run.sh staging|prod [options ansible-playbook, ex. --check --diff]
set -euo pipefail
cd "$(dirname "$0")"

ENV_NAME="${1:-}"
case "$ENV_NAME" in
  staging | prod) shift ;;
  *) echo "Usage : $0 staging|prod [options ansible-playbook]" >&2; exit 1 ;;
esac

TF_DIR="../terraform/environments/$ENV_NAME"
VAULT_PASS="$HOME/.ansible/trackfleet_vault_pass"

[ -f "$VAULT_PASS" ] || { echo "Mot de passe du coffre introuvable ($VAULT_PASS) : lancer ./make_vault.sh $ENV_NAME." >&2; exit 1; }

# Sans état Terraform, "output -raw" répond avec un code de succès et une valeur
# VIDE : tester le code de retour ne suffit donc pas. On exige une valeur non vide,
# faute de quoi l'environnement n'est pas déployé et on le dit clairement, plutôt
# que de lancer Ansible avec un hôte de base de données vide.
tf_output() {
  local value
  value="$(terraform -chdir="$TF_DIR" output -raw "$1" 2> /dev/null)" || value=""
  [ -n "$value" ] || { echo "Sortie Terraform '$1' vide ou introuvable : l'environnement $ENV_NAME est-il déployé (apply.sh) ?" >&2; exit 1; }
  printf '%s' "$value"
}

RDS_HOST="$(tf_output rds_address)"
DB_NAME="$(tf_output db_name)"
DB_USER="$(tf_output db_username)"

# --limit restreint le playbook au groupe de l'environnement : une instance d'un
# autre environnement, si elle apparaît dans l'inventaire, n'est jamais touchée.
ansible-playbook site.yml \
  --limit "$ENV_NAME" \
  --vault-password-file "$VAULT_PASS" \
  -e "rds_host=${RDS_HOST}" \
  -e "db_name=${DB_NAME}" \
  -e "db_user=${DB_USER}" \
  "$@"
