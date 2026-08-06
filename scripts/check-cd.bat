@echo off
setlocal EnableExtensions DisableDelayedExpansion
chcp 65001 >nul

if not defined APP_NAMESPACE set "APP_NAMESPACE=de-ai-12"

echo ============================================================
echo Argo CD Application
echo ============================================================
kubectl get application de-ai-12 -n argocd -o wide

echo.
echo ============================================================
echo Argo CD Pods
echo ============================================================
kubectl get pods -n argocd -o wide

echo.
echo ============================================================
echo Application Resources
echo ============================================================
kubectl get pods,svc,ingress,hpa,pdb -n "%APP_NAMESPACE%" -o wide

echo.
echo ============================================================
echo Public ALB
echo ============================================================
kubectl get ingress public-alb -n "%APP_NAMESPACE%"

for /f "usebackq delims=" %%A in (`kubectl get ingress public-alb -n "%APP_NAMESPACE%" -o jsonpath^="{.status.loadBalancer.ingress[0].hostname}" 2^>nul`) do set "ALB_HOST=%%A"

if defined ALB_HOST (
  echo.
  echo URL: http://%ALB_HOST%
) else (
  echo.
  echo ALB 주소가 아직 생성되지 않았습니다.
)

exit /b 0
