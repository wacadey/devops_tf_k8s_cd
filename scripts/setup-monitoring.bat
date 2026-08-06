@echo off
setlocal EnableExtensions DisableDelayedExpansion
chcp 65001 >nul

rem monitoring-application.yaml.tpl을 실제 GitHub 저장소 정보로 치환하고 Argo CD에 등록한다.
rem 인자 1: GitHub 소유자, 인자 2: CD 저장소명, 인자 3: 브랜치명이다.
set "GITHUB_OWNER=%~1"
set "CD_REPOSITORY=%~2"
set "CD_BRANCH=%~3"

rem 선택 인자에 기본값을 설정한다.
if not defined CD_REPOSITORY set "CD_REPOSITORY=tf-k8s-cd"
if not defined CD_BRANCH set "CD_BRANCH=main"

if not defined GITHUB_OWNER (
  echo 사용법: scripts\setup-monitoring.bat GitHub_ID [CD저장소명] [브랜치]
  echo 예시: scripts\setup-monitoring.bat my-id tf-k8s-cd main
  exit /b 1
)

rem kubectl이 현재 EKS 클러스터에 연결되어 있는지 확인한다.
kubectl cluster-info >nul 2>&1
if errorlevel 1 (
  echo [ERROR] kubectl이 EKS 클러스터에 연결되어 있지 않습니다.
  exit /b 1
)

rem 현재 BAT 파일 기준으로 저장소 루트와 입출력 파일 경로를 계산한다.
set "ROOT_DIR=%~dp0.."
set "TEMPLATE_FILE=%ROOT_DIR%\argocd\monitoring-application.yaml.tpl"
set "OUTPUT_FILE=%ROOT_DIR%\argocd\monitoring-application.generated.yaml"

rem PowerShell을 사용해 템플릿 문자열을 실제 값으로 치환한다.
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$text = Get-Content -Raw -Encoding UTF8 '%TEMPLATE_FILE%';" ^
  "$text = $text.Replace('${GITHUB_OWNER}', '%GITHUB_OWNER%');" ^
  "$text = $text.Replace('${CD_REPOSITORY}', '%CD_REPOSITORY%');" ^
  "$text = $text.Replace('${CD_BRANCH}', '%CD_BRANCH%');" ^
  "[System.IO.File]::WriteAllText('%OUTPUT_FILE%', $text, (New-Object System.Text.UTF8Encoding($false)))"
if errorlevel 1 (
  echo [ERROR] Argo CD Application 템플릿 생성에 실패했습니다.
  exit /b 1
)

rem 렌더링된 Application을 Argo CD namespace에 적용한다.
kubectl apply -f "%OUTPUT_FILE%"
if errorlevel 1 (
  echo [ERROR] Argo CD Application 적용에 실패했습니다.
  exit /b 1
)

echo [OK] Argo CD monitoring Application 등록 완료
echo      생성 파일: %OUTPUT_FILE%
echo      확인 명령: kubectl get application -n argocd de-ai-12-monitoring
exit /b 0
