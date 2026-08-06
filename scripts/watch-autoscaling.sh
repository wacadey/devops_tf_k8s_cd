#!/usr/bin/env bash
# macOS/Linux에서 HPA, Pod, Node 상태를 2초 간격으로 함께 표시한다.
set -euo pipefail

while true; do
  clear
  echo "========== HPA =========="
  kubectl get hpa -n de-ai-12 || true
  echo
  echo "========== POD =========="
  kubectl get pods -n de-ai-12 -o wide || true
  echo
  echo "========== POD METRICS =========="
  kubectl top pods -n de-ai-12 || true
  echo
  echo "========== NODE =========="
  kubectl get nodes || true
  sleep 2
done
