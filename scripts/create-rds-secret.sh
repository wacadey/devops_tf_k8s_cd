#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CI_INFRA_DIR="${1:-${CI_INFRA_DIR:-${ROOT_DIR}/../tf-k8s-ci/infra}}"
APP_NAMESPACE="${APP_NAMESPACE:-de-ai-12}"

for command_name in terraform aws kubectl python3; do
  if ! command -v "${command_name}" >/dev/null 2>&1; then
    echo "[ERROR] 필수 명령을 찾을 수 없습니다: ${command_name}" >&2
    exit 1
  fi
done

AWS_REGION="$(terraform -chdir="${CI_INFRA_DIR}" output -raw aws_region)"
CLUSTER_NAME="$(terraform -chdir="${CI_INFRA_DIR}" output -raw cluster_name)"
RDS_HOST="$(terraform -chdir="${CI_INFRA_DIR}" output -raw rds_endpoint)"
RDS_PORT="$(terraform -chdir="${CI_INFRA_DIR}" output -raw rds_port)"
RDS_DB_NAME="$(terraform -chdir="${CI_INFRA_DIR}" output -raw rds_db_name)"
RDS_SECRET_ARN="$(terraform -chdir="${CI_INFRA_DIR}" output -raw rds_master_secret_arn)"

aws eks update-kubeconfig \
  --region "${AWS_REGION}" \
  --name "${CLUSTER_NAME}"

SECRET_JSON_FILE="$(mktemp)"
DB_ENV_FILE="$(mktemp)"

cleanup() {
  rm -f "${SECRET_JSON_FILE}" "${DB_ENV_FILE}"
}
trap cleanup EXIT

aws secretsmanager get-secret-value \
  --region "${AWS_REGION}" \
  --secret-id "${RDS_SECRET_ARN}" \
  --query SecretString \
  --output text > "${SECRET_JSON_FILE}"

python3 "${ROOT_DIR}/scripts/secret_to_env.py" \
  --secret-json "${SECRET_JSON_FILE}" \
  --output "${DB_ENV_FILE}" \
  --db-host "${RDS_HOST}" \
  --db-port "${RDS_PORT}" \
  --db-name "${RDS_DB_NAME}"

kubectl create namespace "${APP_NAMESPACE}" \
  --dry-run=client \
  -o yaml | kubectl apply -f -

kubectl create secret generic rds-secret \
  --namespace "${APP_NAMESPACE}" \
  --from-env-file="${DB_ENV_FILE}" \
  --dry-run=client \
  -o yaml | kubectl apply -f -

kubectl label secret rds-secret \
  --namespace "${APP_NAMESPACE}" \
  app.kubernetes.io/part-of=de-ai-12 \
  --overwrite

echo "[OK] ${APP_NAMESPACE}/rds-secret 생성 완료"
