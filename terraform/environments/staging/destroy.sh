#!/usr/bin/env bash
# Détruit l'environnement dont ce dossier porte le nom. -refresh=false évite la
# relecture de l'Object Lock du bucket, interdite par une politique du compte
# (voir apply.sh) : sans lui, la destruction échouerait avant de commencer.
set -euo pipefail
cd "$(dirname "$0")"

VARS="$(basename "$PWD").tfvars"
[ -f "$VARS" ] || { echo "Fichier $VARS introuvable." >&2; exit 1; }

terraform destroy -refresh=false -var-file="$VARS" "$@"
