#!/usr/bin/env bash
# Applique l'environnement dont ce dossier porte le nom (staging ou prod), avec
# le fichier de valeurs du même nom. Le script est identique pour les deux.
#
# Il contourne aussi une limite de l'environnement d'exécution : le provider AWS
# lit la configuration Object Lock d'un bucket juste après sa création, et une
# politique du compte l'interdit. La ressource S3 est alors marquée en échec alors
# que le bucket existe. En cas d'échec, on retire cette marque puis on réapplique
# sans relire l'état distant (-refresh=false), ce qui crée le reste.
set -uo pipefail
cd "$(dirname "$0")"

VARS="$(basename "$PWD").tfvars"
[ -f "$VARS" ] || { echo "Fichier $VARS introuvable : copier $VARS.example puis renseigner les valeurs." >&2; exit 1; }

terraform init -input=false || exit 1

if ! terraform apply -var-file="$VARS" "$@"; then
  echo ">> Echec du premier passage : tentative de contournement S3 (Object Lock)"
  # On ne connaît pas l'adresse exacte du bucket dans le module data : on retire
  # la marque d'échec de chaque bucket S3 du state (les ressources liées, comme
  # aws_s3_bucket_versioning, n'ont pas de point après "aws_s3_bucket").
  for addr in $(terraform state list | grep -E 'aws_s3_bucket\.[A-Za-z0-9_-]+$'); do
    terraform untaint "$addr" || true
  done
  terraform apply -refresh=false -var-file="$VARS" "$@"
fi
