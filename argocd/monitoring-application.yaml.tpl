# Argo CD가 Prometheus/Grafana Helm Chart와 이 저장소의 추가 리소스를 함께 관리한다.
# 아래 ${GITHUB_OWNER}, ${CD_REPOSITORY}, ${CD_BRANCH} 값은 설치 스크립트가 실제 값으로 치환한다.
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  # Argo CD 화면에 표시될 모니터링 Application 이름이다.
  name: de-ai-12-monitoring
  # Application 리소스는 Argo CD가 설치된 namespace에 생성한다.
  namespace: argocd
  # Application 삭제 시 Argo CD가 생성한 하위 리소스도 정리하도록 finalizer를 지정한다.
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  # 기존 AppProject를 사용한다. 프로젝트명이 다르면 이 값을 변경한다.
  project: default

  # 여러 source를 사용하여 외부 Helm Chart와 Git 저장소의 설정을 하나의 Application으로 관리한다.
  sources:
    # 첫 번째 source: Prometheus Community의 kube-prometheus-stack Helm Chart이다.
    - repoURL: https://prometheus-community.github.io/helm-charts
      chart: kube-prometheus-stack
      # 재현 가능한 설치를 위해 Chart 버전을 고정한다.
      targetRevision: 87.0.1
      helm:
        # Helm release 이름을 고정하여 Service/Secret 이름을 예측 가능하게 만든다.
        releaseName: kube-prometheus-stack
        # 두 번째 Git source의 values 파일을 참조한다.
        valueFiles:
          - $values/monitoring/kube-prometheus-stack-values.yaml

    # 두 번째 source: 현재 tf-k8s-cd 저장소를 values 전용 source로 등록한다.
    - repoURL: https://github.com/${GITHUB_OWNER}/${CD_REPOSITORY}.git
      targetRevision: ${CD_BRANCH}
      ref: values

    # 세 번째 source: Dashboard, ServiceMonitor, Alert Rule 등 추가 리소스를 배포한다.
    - repoURL: https://github.com/${GITHUB_OWNER}/${CD_REPOSITORY}.git
      targetRevision: ${CD_BRANCH}
      path: monitoring/resources

  destination:
    # 현재 Argo CD가 설치된 Kubernetes 클러스터를 의미한다.
    server: https://kubernetes.default.svc
    # Prometheus와 Grafana를 분리된 monitoring namespace에 설치한다.
    namespace: monitoring

  syncPolicy:
    automated:
      # Git에서 제거한 리소스를 클러스터에서도 자동 제거한다.
      prune: true
      # 클러스터에서 수동 변경된 값을 Git 선언 상태로 자동 복구한다.
      selfHeal: true
      # 리소스가 하나도 없는 최초 설치 상태에서도 동기화를 허용한다.
      allowEmpty: false
    syncOptions:
      # monitoring namespace가 없으면 Argo CD가 자동 생성한다.
      - CreateNamespace=true
      # CRD가 먼저 생성된 후 ServiceMonitor 등의 리소스를 검증하도록 한다.
      - SkipDryRunOnMissingResource=true
      # 대형 CRD 적용 시 kubectl annotation 크기 제한을 피한다.
      - ServerSideApply=true
    retry:
      # 일시적인 CRD/API 준비 지연이 발생하면 자동 재시도한다.
      limit: 5
      backoff:
        duration: 10s
        factor: 2
        maxDuration: 3m
