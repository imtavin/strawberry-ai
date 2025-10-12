# scripts/setup_unified.ps1
Write-Host " Configurando Strawberry AI com Python 3.10..." -ForegroundColor Green

# Verificar se Python 3.10 está instalado
$python310 = Get-Command "python3.10" -ErrorAction SilentlyContinue
if (-not $python310) {
    $python310 = Get-Command "python" -ErrorAction SilentlyContinue
    if ($python310) {
        $version = & python --version
        if ($version -notlike "*3.10*") {
            Write-Host " Python 3.10 não encontrado!" -ForegroundColor Red
            Write-Host " Baixe e instale: https://www.python.org/ftp/python/3.10.11/python-3.10.11-amd64.exe" -ForegroundColor Yellow
            Write-Host " MARQUE 'Add Python to PATH' durante a instalação" -ForegroundColor Yellow
            exit 1
        }
    } else {
        Write-Host " Python não encontrado!" -ForegroundColor Red
        Write-Host " Baixe e instale: https://www.python.org/ftp/python/3.10.11/python-3.10.11-amd64.exe" -ForegroundColor Yellow
        exit 1
    }
}

Write-Host " Python 3.10 encontrado" -ForegroundColor Green

# Remover venvs antigos se existirem
Write-Host "`n  Limpando ambientes antigos..." -ForegroundColor Yellow
if (Test-Path "backend\venv") { Remove-Item -Recurse -Force backend\venv }
if (Test-Path "frontend\venv") { Remove-Item -Recurse -Force frontend\venv }

# CONFIGURAR BACKEND
Write-Host "`n Configurando BACKEND..." -ForegroundColor Cyan
cd backend
python -m venv venv
.\venv\Scripts\Activate.ps1

# Instalar dependências em ordem específica para evitar conflitos
pip install --upgrade pip
pip install "setuptools==68.2.2" "wheel==0.43.0"

# Core primeiro
pip install "numpy==1.26.4"
pip install "pillow==10.4.0"
pip install "opencv-python-headless==4.10.0.84"

# Depois o resto
pip install "psutil==5.9.8"
pip install "flask==3.1.0" "flask-cors==5.0.1"
pip install "tflite-runtime==2.15.0"

# Utilitários
pip install "colorama==0.4.6" "packaging==25.0" "netifaces==0.11.0"

Write-Host " Backend configurado!" -ForegroundColor Green

# CONFIGURAR FRONTEND
Write-Host "`n Configurando FRONTEND..." -ForegroundColor Cyan
cd ..\frontend
python -m venv venv
.\venv\Scripts\Activate.ps1

# Instalar dependências
pip install --upgrade pip
pip install "setuptools==68.2.2" "wheel==0.43.0"

# Core primeiro
pip install "numpy==1.26.4"
pip install "pillow==10.4.0"
pip install "opencv-python==4.10.0.84"

# UI
pip install "customtkinter==5.2.2" "darkdetect==0.8.0"

# Utilitários
pip install "psutil==5.9.8" "requests==2.31.0"
pip install "colorama==0.4.6" "packaging==25.0" "netifaces==0.11.0"

Write-Host " Frontend configurado!" -ForegroundColor Green

cd ..

# TESTES
Write-Host "`n Testando instalações..." -ForegroundColor Cyan

Write-Host "Backend:" -ForegroundColor Yellow
cd backend
.\venv\Scripts\Activate.ps1
python -c "
import sys
print(f'Python: {sys.version}')
import numpy as np
print(f'NumPy: {np.__version__}')
import cv2
print(f'OpenCV: {cv2.__version__}')
import tflite_runtime
print('TFLite Runtime: OK')
import flask
print(f'Flask: {flask.__version__}')
print(' Backend - TODAS DEPENDÊNCIAS OK!')
"

Write-Host "`nFrontend:" -ForegroundColor Yellow
cd ..\frontend
.\venv\Scripts\Activate.ps1
python -c "
import sys
print(f'Python: {sys.version}')
import customtkinter as ctk
print(f'CustomTkinter: {ctk.__version__}')
import cv2
print(f'OpenCV: {cv2.__version__}')
import numpy as np
print(f'NumPy: {np.__version__}')
print(' Frontend - TODAS DEPENDÊNCIAS OK!')
"

cd ..
Write-Host "`n CONFIGURAÇÃO UNIFICADA CONCLUÍDA!" -ForegroundColor Green
Write-Host "Python 3.10 funcionando para Backend e Frontend!" -ForegroundColor White
Write-Host "`nPara iniciar:" -ForegroundColor Yellow
Write-Host "  Backend:  scripts\start_backend.ps1" -ForegroundColor White
Write-Host "  Frontend: scripts\start_frontend.ps1" -ForegroundColor White