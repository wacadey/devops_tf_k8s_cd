#!/usr/bin/env bash
# monitoring-application.yaml.tpl을 실제 GitHub 저장소 정보로 치환하고 Argo CD에 등록한다.
set -euo pipefail

# 인자: GitHub 소유자, CD 저장소 이름, 브랜치 이름이다.
GITHUB_OWNER="${1:-}"
CD_REPOSITORY="${2:-tf-k8s-cd}"
CD_BRANCH="${3:-main}"

if [[ -z "${GITHUB_OWNER}" ]]; then
  echo "사용법: ./scripts/setup-monitoring.sh GitHub_ID [CD저장소명] [브랜치]"
  echo "예시: ./scripts/setup-monitoring.sh my-id tf-k8s-cd main"
  exit 1
fi

# kubectl 연결 상태를 사전에 검증한다.
if ! kubectl cluster-info >/dev/null 2>&1; then
  echo "[ERROR] kubectl이 EKS 클러스터에 연결되어 있지 않습니다."
  exit 1
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMPLATE_FILE="${ROOT_DIR}/argocd/monitoring-application.yaml.tpl"
OUTPUT_FILE="${ROOT_DIR}/argocd/monitoring-application.generated.yaml"

# Python 표준 라이브러리만 사용해 운영체제별 envsubst 차이를 제거한다.
python3 - "${TEMPLATE_FILE}" "${OUTPUT_FILE}" "${GITHUB_OWNER}" "${CD_REPOSITORY}" "${CD_BRANCH}" <<'PY'
from pathlib import Path
import sys

template_path, output_path, owner, repository, branch = sys.argv[1:]
text = Path(template_path).read_text(encoding="utf-8")
text = text.replace("${GITHUB_OWNER}", owner)
text = text.replace("${CD_REPOSITORY}", repository)
text = text.replace("${CD_BRANCH}", branch)
Path(output_path).write_text(text, encoding="utf-8")
PY

# 렌더링된 Argo CD Application을 클러스터에 적용한다.
kubectl apply -f "${OUTPUT_FILE}"

echo "[OK] Argo CD monitoring Application 등록 완료"
echo "     생성 파일: ${OUTPUT_FILE}"
echo "     확인 명령: kubectl get application -n argocd de-ai-12-monitoring"
