@echo off
setlocal EnableExtensions EnableDelayedExpansion
title myERP - Update and Run
color 0B
echo ============================================================
echo                 myERP - UPDATE AND RUN
echo ============================================================
echo.

set "REPO_URL=https://github.com/moustafaadelammar/myERP.git"
set "BRANCH=feature/local-fullstack"
set "SCRIPT_DIR=%~dp0"
if exist "%SCRIPT_DIR%.git" (set "PROJECT=%SCRIPT_DIR:~0,-1%") else (set "PROJECT=%USERPROFILE%\myERP")
set "COMPOSE=docker-compose.local.yml"

echo [1/7] Checking Git and Docker...
where git >nul 2>&1
if errorlevel 1 (
  echo [ERROR] Git is not installed. Install Git for Windows and rerun.
  start "" "https://git-scm.com/download/win"
  pause
  exit /b 1
)
where docker >nul 2>&1
if errorlevel 1 (
  echo [ERROR] Docker Desktop is not installed. Install it and rerun.
  start "" "https://www.docker.com/products/docker-desktop/"
  pause
  exit /b 1
)
docker info >nul 2>&1
if errorlevel 1 (
  echo [INFO] Starting Docker Desktop...
  start "" "C:\Program Files\Docker\Docker\Docker Desktop.exe" >nul 2>&1
  start "" "%LOCALAPPDATA%\Programs\Docker\Docker Desktop.exe" >nul 2>&1
  set /a WAIT=0
  :docker_wait
  timeout /t 5 /nobreak >nul
  docker info >nul 2>&1
  if not errorlevel 1 goto docker_ready
  set /a WAIT+=5
  if !WAIT! GEQ 120 (
    echo [ERROR] Docker Engine is not ready. Open Docker Desktop, wait for Running, then rerun.
    pause
    exit /b 1
  )
  goto docker_wait
)
:docker_ready
echo [OK] Docker Engine is running.

echo.
echo [2/7] Downloading/updating source from GitHub...
if not exist "%PROJECT%\.git" (
  if exist "%PROJECT%" (
    echo [ERROR] %PROJECT% exists but is not a Git repository.
    echo Move or rename that folder, then rerun.
    pause
    exit /b 1
  )
  git clone --branch "%BRANCH%" "%REPO_URL%" "%PROJECT%"
  if errorlevel 1 goto fail
) else (
  cd /d "%PROJECT%"
  git fetch origin --prune
  if errorlevel 1 goto fail
  git checkout "%BRANCH%" >nul 2>&1
  if errorlevel 1 git checkout -b "%BRANCH%" "origin/%BRANCH%"
  git reset --hard "origin/%BRANCH%"
  if errorlevel 1 goto fail
  git clean -fd
)
cd /d "%PROJECT%"
if errorlevel 1 goto fail
for /f "delims=" %%G in ('git rev-parse --short HEAD') do set "COMMIT=%%G"
echo [OK] Source updated to commit !COMMIT!.

echo.
echo [3/7] Validating configuration and JavaScript syntax...
if not exist "%COMPOSE%" (
  echo [ERROR] docker-compose.local.yml is missing.
  goto fail
)
docker compose -f "%COMPOSE%" config >nul
if errorlevel 1 goto fail
docker run --rm -v "%PROJECT%\backend:/app" -w /app node:20-alpine node --check src/server.js
if errorlevel 1 (
  echo [ERROR] Backend JavaScript has a syntax error; refusing to build a broken API.
  goto fail
)
echo [OK] Configuration and API syntax are valid.

echo.
echo [4/7] Rebuilding and starting the stack...
docker compose -f "%COMPOSE%" down --remove-orphans
if errorlevel 1 goto fail
docker compose -f "%COMPOSE%" up -d --build
if errorlevel 1 goto fail

echo.
echo [5/7] Waiting for API health...
set /a WAIT=0
:api_wait
powershell -NoProfile -ExecutionPolicy Bypass -Command "try { $r=Invoke-WebRequest -UseBasicParsing -TimeoutSec 3 http://localhost:4000/health; if($r.StatusCode -eq 200){exit 0}else{exit 1} } catch { exit 1 }" >nul 2>&1
if not errorlevel 1 goto api_ready
timeout /t 5 /nobreak >nul
set /a WAIT+=5
if !WAIT! GEQ 120 (
  echo [ERROR] API did not become healthy. Showing API logs...
  docker compose -f "%COMPOSE%" logs --tail=120 api
  goto fail
)
goto api_wait
:api_ready
echo [OK] API is healthy.

echo.
echo [6/7] Checking website...
powershell -NoProfile -ExecutionPolicy Bypass -Command "try { $r=Invoke-WebRequest -UseBasicParsing -TimeoutSec 5 http://localhost:8080/health; if($r.StatusCode -eq 200){exit 0}else{exit 1} } catch { exit 1 }" >nul 2>&1
if errorlevel 1 (
  echo [ERROR] Website health check failed.
  docker compose -f "%COMPOSE%" logs --tail=80 web
  goto fail
)
echo [OK] Website is healthy.

echo.
echo [7/7] Opening ERP...
echo URL: http://localhost:8080
echo API: http://localhost:4000/health
echo Login email: admin@myerb.local
echo Login password: Admin@123
start "" "http://localhost:8080"
echo.
echo [OK] myERP is running. After pushing new code to GitHub, run this SAME CMD file to fetch and rebuild.
pause
exit /b 0

:fail
echo.
echo [ERROR] Startup failed. Current services:
docker compose -f "%COMPOSE%" ps
echo.
echo Recent API logs:
docker compose -f "%COMPOSE%" logs --tail=100 api
echo.
echo Project folder: %PROJECT%
pause
exit /b 1
