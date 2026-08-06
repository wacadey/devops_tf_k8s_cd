@echo off
setlocal EnableExtensions DisableDelayedExpansion
chcp 65001 >nul

set "ROOT_DIR=%~dp0.."
for %%I in ("%ROOT_DIR%") do set "ROOT_DIR=%%~fI"

if "%~1"=="" (
  if defined CI_INFRA_DIR (
    set "CI_INFRA_DIR=%CI_INFRA_DIR%"
  ) else (
    set "CI_INFRA_DIR=%ROOT_DIR%\..\tf-k8s-ci\infra"
  )
) else (
  set "CI_INFRA_DIR=%~1"
)

for %%I in ("%CI_INFRA_DIR%") do set "CI_INFRA_DIR=%%~fI"
if not defined APP_NAMESPACE set "APP_NAMESPACE=de-ai-12"

set "SECRET_JSON_FILE=%TEMP%\de-ai-12-rds-%RANDOM%.json"
set "DB_ENV_FILE=%TEMP%\de-ai-12-rds-%RANDOM%.env"

call :terraform_output AWS_REGION aws_region
if errorlevel 1 goto :error
call :terraform_output CLUSTER_NAME cluster_name
if errorlevel 1 goto :error
call :terraform_output RDS_HOST rds_endpoint
if errorlevel 1 goto :error
call :terraform_output RDS_PORT rds_port
if errorlevel 1 goto :error
call :terraform_output RDS_DB_NAME rds_db_name
if errorlevel 1 goto :error
call :terraform_output RDS_SECRET_ARN rds_master_secret_arn
if errorlevel 1 goto :error

aws eks update-kubeconfig --region "%AWS_REGION%" --name "%CLUSTER_NAME%"
if errorlevel 1 goto :error

aws secretsmanager get-secret-value ^
  --region "%AWS_REGION%" ^
  --secret-id "%RDS_SECRET_ARN%" ^
  --query SecretString ^
  --output text > "%SECRET_JSON_FILE%"
if errorlevel 1 goto :error

python "%ROOT_DIR%\scripts\secret_to_env.py" ^
  --secret-json "%SECRET_JSON_FILE%" ^
  --output "%DB_ENV_FILE%" ^
  --db-host "%RDS_HOST%" ^
  --db-port "%RDS_PORT%" ^
  --db-name "%RDS_DB_NAME%"
if errorlevel 1 goto :error

kubectl create namespace "%APP_NAMESPACE%" --dry-run=client -o yaml | kubectl apply -f -
if errorlevel 1 goto :error

kubectl create secret generic rds-secret ^
  --namespace "%APP_NAMESPACE%" ^
  --from-env-file="%DB_ENV_FILE%" ^
  --dry-run=client ^
  -o yaml | kubectl apply -f -
if errorlevel 1 goto :error

kubectl label secret rds-secret ^
  --namespace "%APP_NAMESPACE%" ^
  app.kubernetes.io/part-of=de-ai-12 ^
  --overwrite
if errorlevel 1 goto :error

del /q "%SECRET_JSON_FILE%" >nul 2>&1
del /q "%DB_ENV_FILE%" >nul 2>&1

echo [OK] %APP_NAMESPACE%/rds-secret 생성 완료
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
del /q "%SECRET_JSON_FILE%" >nul 2>&1
del /q "%DB_ENV_FILE%" >nul 2>&1
echo [ERROR] RDS Secret 생성 중 오류가 발생했습니다.
exit /b %EXIT_CODE%
