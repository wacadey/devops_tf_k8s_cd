apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: de-ai-12
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: de-ai-12

  source:
    repoURL: "__CD_REPO_URL__"
    targetRevision: main
    path: k8s/overlays/dev

  destination:
    server: https://kubernetes.default.svc
    namespace: de-ai-12

  syncPolicy:
    automated:
      enabled: true
      prune: true
      selfHeal: true
      allowEmpty: false

    syncOptions:
      - CreateNamespace=true
      - ApplyOutOfSyncOnly=true
      - PruneLast=true
      - RespectIgnoreDifferences=true

    retry:
      limit: 5
      refresh: true
      backoff:
        duration: 10s
        factor: 2
        maxDuration: 3m

  ignoreDifferences:
    - group: apps
      kind: Deployment
      jsonPointers:
        - /spec/replicas

  revisionHistoryLimit: 10
