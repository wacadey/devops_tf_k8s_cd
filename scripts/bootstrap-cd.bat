@echo off
setlocal EnableExtensions DisableDelayedExpansion
chcp 65001 >nul

if "%~1"=="" (
  echo 사용법: %~nx0 GitHub_ID\tf-k8s-cd [tf-k8s-ci\infra 경로]
  exit /b 1
)

set "ROOT_DIR=%~dp0.."
for %%I in ("%ROOT_DIR%") do set "ROOT_DIR=%%~fI"

set "CD_REPOSITORY=%~1"
set "CD_REPOSITORY=%CD_REPOSITORY:\=/%"
if "%CD_REPOSITORY:~-4%"==".git" set "CD_REPOSITORY=%CD_REPOSITORY:~0,-4%"

if "%~2"=="" (
  if defined CI_INFRA_DIR (
    set "CI_INFRA_DIR=%CI_INFRA_DIR%"
  ) else (
    set "CI_INFRA_DIR=%ROOT_DIR%\..\devops_tf_k8s_ci\infra"
  )
) else (
  set "CI_INFRA_DIR=%~2"
)

for %%I in ("%CI_INFRA_DIR%") do set "CI_INFRA_DIR=%%~fI"

set "CD_REPO_URL=https://github.com/%CD_REPOSITORY%.git"
if not defined INITIAL_IMAGE_TAG set "INITIAL_IMAGE_TAG=dev-latest"
if not defined APP_NAMESPACE set "APP_NAMESPACE=de-ai-12"
if not defined AUTO_PUSH set "AUTO_PUSH=true"

call "%ROOT_DIR%\scripts\configure-manifests.bat" "%CI_INFRA_DIR%" "%INITIAL_IMAGE_TAG%"
if errorlevel 1 exit /b 1

git -C "%ROOT_DIR%" diff --quiet -- k8s/overlays/dev/kustomization.yaml
if errorlevel 1 (
  git -C "%ROOT_DIR%" add k8s/overlays/dev/kustomization.yaml
  if errorlevel 1 exit /b 1

  git -C "%ROOT_DIR%" commit -m "chore(cd): configure initial ECR images"
  if errorlevel 1 exit /b 1

  if /I "%AUTO_PUSH%"=="true" (
    git -C "%ROOT_DIR%" push origin main
    if errorlevel 1 exit /b 1
  ) else (
    echo [INFO] AUTO_PUSH=false이므로 직접 git push를 실행하세요.
  )
)

call :terraform_output AWS_REGION aws_region
if errorlevel 1 exit /b 1
call :terraform_output CLUSTER_NAME cluster_name
if errorlevel 1 exit /b 1

aws eks update-kubeconfig --region "%AWS_REGION%" --name "%CLUSTER_NAME%"
if errorlevel 1 exit /b 1

call "%ROOT_DIR%\scripts\install-argocd.bat"
if errorlevel 1 exit /b 1

call "%ROOT_DIR%\scripts\create-rds-secret.bat" "%CI_INFRA_DIR%"
if errorlevel 1 exit /b 1

if defined ARGOCD_GITHUB_TOKEN (
  if not defined ARGOCD_GITHUB_USERNAME (
    for /f "tokens=1 delims=/" %%A in ("%CD_REPOSITORY%") do set "ARGOCD_GITHUB_USERNAME=%%A"
  )

  kubectl create secret generic tf-k8s-cd-repository ^
    --namespace argocd ^
    --from-literal=type=git ^
    --from-literal=url="%CD_REPO_URL%" ^
    --from-literal=username="%ARGOCD_GITHUB_USERNAME%" ^
    --from-literal=password="%ARGOCD_GITHUB_TOKEN%" ^
    --dry-run=client ^
    -o yaml | kubectl apply -f -
  if errorlevel 1 exit /b 1

  kubectl label secret tf-k8s-cd-repository ^
    --namespace argocd ^
    argocd.argoproj.io/secret-type=repository ^
    --overwrite
  if errorlevel 1 exit /b 1
) else (
  echo [INFO] ARGOCD_GITHUB_TOKEN이 없어 공개 저장소로 구성합니다.
)

set "RENDER_DIR=%TEMP%\tf-k8s-cd-render-%RANDOM%"
mkdir "%RENDER_DIR%"
if errorlevel 1 exit /b 1

python "%ROOT_DIR%\scripts\render_argocd.py" ^
  --template-dir "%ROOT_DIR%\argocd" ^
  --output-dir "%RENDER_DIR%" ^
  --repo-url "%CD_REPO_URL%"
if errorlevel 1 goto :error

kubectl apply -f "%RENDER_DIR%\project.yaml"
if errorlevel 1 goto :error

kubectl apply -f "%RENDER_DIR%\application.yaml"
if errorlevel 1 goto :error

rmdir /s /q "%RENDER_DIR%" >nul 2>&1

echo.
echo ============================================================
echo Argo CD GitOps CD 구성이 완료되었습니다.
echo Cluster    : %CLUSTER_NAME%
echo Namespace  : %APP_NAMESPACE%
echo Repository : %CD_REPO_URL%
echo.
echo 상태 확인:
echo scripts\check-cd.bat
echo.
echo Argo CD UI:
echo scripts\open-argocd.bat
echo ============================================================
exit /b 0

:terraform_output
set "%~1="
for /f "usebackq delims=" %%A in (`terraform -chdir^="%CI_INFRA_DIR%" output -raw %~2`) do set "%~1=%%A"
if not defined %~1 (
  echo [ERROR] Terraform output을 읽지 못했습니다: %~2
  exit /b 1
)
exit /b 0

:error
set "EXIT_CODE=%ERRORLEVEL%"
if "%EXIT_CODE%"=="0" set "EXIT_CODE=1"
rmdir /s /q "%RENDER_DIR%" >nul 2>&1
echo [ERROR] CD 구성 중 오류가 발생했습니다.
exit /b %EXIT_CODE%
