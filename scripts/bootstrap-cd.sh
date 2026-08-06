#!/usr/bin/env bash
set -Eeuo pipefail

if [[ $# -lt 1 ]]; then
  echo "사용법: $0 GitHub_ID/tf-k8s-cd [tf-k8s-ci/infra 경로]" >&2
  exit 1
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CD_REPOSITORY="${1%.git}"
CD_REPOSITORY="${CD_REPOSITORY//\\//}"
CI_INFRA_DIR="${2:-${CI_INFRA_DIR:-${ROOT_DIR}/../tf-k8s-ci/infra}}"
CD_REPO_URL="https://github.com/${CD_REPOSITORY}.git"
INITIAL_IMAGE_TAG="${INITIAL_IMAGE_TAG:-dev-latest}"
APP_NAMESPACE="${APP_NAMESPACE:-de-ai-12}"
AUTO_PUSH="${AUTO_PUSH:-true}"

for command_name in git terraform aws kubectl python3; do
  if ! command -v "${command_name}" >/dev/null 2>&1; then
    echo "[ERROR] 필수 명령을 찾을 수 없습니다: ${command_name}" >&2
    exit 1
  fi
done

if ! aws sts get-caller-identity >/dev/null 2>&1; then
  echo "[ERROR] AWS CLI 인증을 확인하세요." >&2
  exit 1
fi

"${ROOT_DIR}/scripts/configure-manifests.sh" \
  "${CI_INFRA_DIR}" \
  "${INITIAL_IMAGE_TAG}"

OVERLAY_FILE="k8s/overlays/dev/kustomization.yaml"

if ! git -C "${ROOT_DIR}" diff --quiet -- "${OVERLAY_FILE}"; then
  git -C "${ROOT_DIR}" add "${OVERLAY_FILE}"
  git -C "${ROOT_DIR}" commit -m "chore(cd): configure initial ECR images"

  if [[ "${AUTO_PUSH}" == "true" ]]; then
    git -C "${ROOT_DIR}" push origin main
  else
    echo "[INFO] AUTO_PUSH=false이므로 직접 git push를 실행하세요."
  fi
fi

AWS_REGION="$(terraform -chdir="${CI_INFRA_DIR}" output -raw aws_region)"
CLUSTER_NAME="$(terraform -chdir="${CI_INFRA_DIR}" output -raw cluster_name)"

aws eks update-kubeconfig \
  --region "${AWS_REGION}" \
  --name "${CLUSTER_NAME}"

"${ROOT_DIR}/scripts/install-argocd.sh"
"${ROOT_DIR}/scripts/create-rds-secret.sh" "${CI_INFRA_DIR}"

if [[ -n "${ARGOCD_GITHUB_TOKEN:-}" ]]; then
  ARGOCD_GITHUB_USERNAME="${ARGOCD_GITHUB_USERNAME:-${CD_REPOSITORY%%/*}}"

  kubectl create secret generic tf-k8s-cd-repository \
    --namespace argocd \
    --from-literal=type=git \
    --from-literal=url="${CD_REPO_URL}" \
    --from-literal=username="${ARGOCD_GITHUB_USERNAME}" \
    --from-literal=password="${ARGOCD_GITHUB_TOKEN}" \
    --dry-run=client \
    -o yaml | kubectl apply -f -

  kubectl label secret tf-k8s-cd-repository \
    --namespace argocd \
    argocd.argoproj.io/secret-type=repository \
    --overwrite
else
  echo "[INFO] ARGOCD_GITHUB_TOKEN이 없어 공개 저장소로 구성합니다."
fi

RENDER_DIR="$(mktemp -d)"
cleanup() {
  rm -rf "${RENDER_DIR}"
}
trap cleanup EXIT

python3 "${ROOT_DIR}/scripts/render_argocd.py" \
  --template-dir "${ROOT_DIR}/argocd" \
  --output-dir "${RENDER_DIR}" \
  --repo-url "${CD_REPO_URL}"

kubectl apply -f "${RENDER_DIR}/project.yaml"
kubectl apply -f "${RENDER_DIR}/application.yaml"

echo
echo "============================================================"
echo "Argo CD GitOps CD 구성이 완료되었습니다."
echo "Cluster    : ${CLUSTER_NAME}"
echo "Namespace  : ${APP_NAMESPACE}"
echo "Repository : ${CD_REPO_URL}"
echo
echo "상태 확인:"
echo "${ROOT_DIR}/scripts/check-cd.sh"
echo
echo "Argo CD UI:"
echo "${ROOT_DIR}/scripts/open-argocd.sh"
echo "============================================================"
