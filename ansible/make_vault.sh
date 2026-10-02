#!/usr/bin/env bash
# Chiffre le mot de passe de la base avec Ansible Vault et l'écrit dans
# group_vars/<env>.yml, à partir du mot de passe déjà présent dans
# terraform/environments/<env>/<env>.tfvars : une seule source de vérité pour le
# secret, jamais retapé ni affiché, et jamais écrit en clair sur le disque.
#
# Usage : ./make_vault.sh staging|prod
#
# Le secret est chiffré EN LIGNE (variable !vault) dans le fichier de l'environnement,
# et non dans un dossier group_vars/<env>/ : Ansible ignore group_vars/<env>.yml
# dès que le dossier du même nom existe, ce qui ferait disparaître sans erreur
# les variables propres à l'environnement.
#
# Le mot de passe du coffre est généré une fois et stocké HORS du dépôt, dans le
# répertoire personnel de la personne qui possède l'environnement. Chaque
# environnement est donc chiffré par son propriétaire : le secret de staging ne se
# déchiffre qu'avec le mot de passe de son propriétaire, celui de prod qu'avec le
# sien. Ansible ne charge que les variables des groupes de l'environnement ciblé,
# donc personne n'a besoin du mot de passe de l'autre.
set -euo pipefail
cd "$(dirname "$0")"

ENV_NAME="${1:-}"
case "$ENV_NAME" in
  staging | prod) ;;
  *) echo "Usage : $0 staging|prod" >&2; exit 1 ;;
esac

VAULT_PASS="$HOME/.ansible/trackfleet_vault_pass"
TFVARS="../terraform/environments/$ENV_NAME/$ENV_NAME.tfvars"
ENV_FILE="group_vars/$ENV_NAME.yml"
START="# >>> vault (bloc genere par make_vault.sh, ne pas modifier a la main)"
END="# <<< vault"

[ -f "$TFVARS" ] || { echo "Fichier $TFVARS introuvable : le créer d'abord depuis son .example." >&2; exit 1; }
[ -f "$ENV_FILE" ] || { echo "Fichier $ENV_FILE introuvable." >&2; exit 1; }

# Droits restreints sur tout ce que le script crée (mot de passe du coffre inclus).
umask 077
mkdir -p "$HOME/.ansible"
[ -f "$VAULT_PASS" ] || openssl rand -base64 24 > "$VAULT_PASS"

DB_PASSWORD="$(sed -n 's/^db_password *= *"\(.*\)"/\1/p' "$TFVARS")"
[ -n "$DB_PASSWORD" ] || { echo "db_password introuvable dans $TFVARS" >&2; exit 1; }

# Le mot de passe passe par l'entrée standard : il n'apparaît ni dans la liste des
# processus ni dans un fichier temporaire. Le fichier de mot de passe du coffre est
# passé ici et non dans ansible.cfg : la ligne du coffre y reste désactivée pour
# qu'Ansible fonctionne aussi sans coffre (lint, vérification de syntaxe).
ENCRYPTED="$(printf '%s' "$DB_PASSWORD" \
  | ansible-vault encrypt_string --vault-password-file "$VAULT_PASS" --stdin-name vault_db_password 2> /dev/null)"
[ -n "$ENCRYPTED" ] || { echo "Le chiffrement a échoué." >&2; exit 1; }

# Remplace le bloc précédent s'il existe, sinon l'ajoute en fin de fichier.
sed -i "\|^${START}\$|,\|^${END}\$|d" "$ENV_FILE"
[ -z "$(tail -c1 "$ENV_FILE")" ] || echo >> "$ENV_FILE"
{
  echo "$START"
  echo "$ENCRYPTED"
  echo "$END"
} >> "$ENV_FILE"

echo "Mot de passe chiffré écrit dans $ENV_FILE"
