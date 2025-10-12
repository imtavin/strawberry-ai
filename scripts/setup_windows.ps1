# scripts/setup_windows_fixed.ps1
Write-Host " Configurando Strawberry AI no Windows..." -ForegroundColor Green

# Encontrar Python automaticamente
$python39Path = @(
    "C:\Users\Gustavo\AppData\Local\Programs\Python\Python39\python.exe",
    "C:\Program Files\Python39\python.exe",
    "$env:LOCALAPPDATA\Programs\Python\Python39\python.exe"
) | Where-Object { Test-Path $_ } | Select-Object -First 1

$python311Path = @(
    "C:\Users\Gustavo\AppData\Local\Programs\Python\Python311\python.exe", 
    "C:\Program Files\Python311\python.exe",
    "$env:LOCALAPPDATA\Programs\Python\Python311\python.exe"
) | Where-Object { Test-Path $_ } | Select-Object -First 1

# Se não encontrou, tentar via PATH
if (-not $python39Path) {
    $python39Path = Get-Command "python3.9" -ErrorAction SilentlyContinue
    if ($python39Path) { $python39Path = $python39Path.Source }
}

if (-not $python311Path) {
    $python311Path = Get-Command "python3.11" -ErrorAction SilentlyContinue  
    if ($python311Path) { $python311Path = $python311Path.Source }
}

# Se ainda não encontrou, tentar python padrão
if (-not $python39Path) {
    $python39Path = Get-Command "python" -ErrorAction SilentlyContinue
    if ($python39Path) { 
        $python39Path = $python39Path.Source
        Write-Host "  Usando Python padrão para backend: $python39Path" -ForegroundColor Yellow
    }
}

if (-not $python311Path) {
    Write-Host " Python 3.11 não encontrado!" -ForegroundColor Red
    Write-Host " Baixe e instale: https://www.python.org/ftp/python/3.11.8/python-3.11.8-amd64.exe" -ForegroundColor Yellow
    Write-Host " Durante a instalação, MARQUE: 'Add Python to PATH'" -ForegroundColor Yellow
    exit 1
}

if (-not $python39Path) {
    Write-Host " Python 3.9 não encontrado!" -ForegroundColor Red
    Write-Host " Baixe e instale: https://www.python.org/ftp/python/3.9.13/python-3.9.13-amd64.exe" -ForegroundColor Yellow
    Write-Host " Durante a instalação, MARQUE: 'Add Python to PATH'" -ForegroundColor Yellow
    exit 1
}

Write-Host " Python 3.9 encontrado: $python39Path" -ForegroundColor Green
Write-Host " Python 3.11 encontrado: $python311Path" -ForegroundColor Green

# Configurar BACKEND com Python 3.9
Write-Host "`n Configurando BACKEND (Python 3.9)..." -ForegroundColor Cyan
Set-Location backend

# Criar venv
& $python39Path -m venv venv

# Ativar venv
.\venv\Scripts\Activate.ps1

# Atualizar pip
python -m pip install --upgrade pip

# Instalar dependências
pip install -r ..\requirements-backend.txt

# Instalações específicas para Windows
pip install netifaces

Write-Host " Backend configurado!" -ForegroundColor Green

# Configurar FRONTEND com Python 3.11
Write-Host "`n Configurando FRONTEND (Python 3.11)..." -ForegroundColor Cyan
Set-Location ..\frontend

# Criar venv
& $python311Path -m venv venv

# Ativar venv
.\venv\Scripts\Activate.ps1

# Atualizar pip
python -m pip install --upgrade pip

# Instalar dependências
pip install -r ..\requirements-frontend.txt

# Instalações específicas para Windows
pip install netifaces

Write-Host " Frontend configurado!" -ForegroundColor Green

# Voltar ao diretório raiz
Set-Location ..

Write-Host "`n Configuração concluída com sucesso!" -ForegroundColor Green
Write-Host "`nPara iniciar os serviços:" -ForegroundColor Yellow
Write-Host "  Backend:  scripts\start_backend.ps1" -ForegroundColor White
Write-Host "  Frontend: scripts\start_frontend.ps1" -ForegroundColor White
Write-Host "  Ambos:    scripts\start_all.ps1" -ForegroundColor White

# Testar as instalações
Write-Host "`n Testando instalações..." -ForegroundColor Cyan

Write-Host "Backend:" -ForegroundColor Yellow
Set-Location backend
.\venv\Scripts\Activate.ps1
python -c "import sys; print(f'Python: {sys.version}'); import numpy; print(f'NumPy: {numpy.__version__}'); import cv2; print(f'OpenCV: {cv2.__version__}')"

Write-Host "`nFrontend:" -ForegroundColor Yellow
Set-Location ..\frontend
.\venv\Scripts\Activate.ps1  
python -c "import sys; print(f'Python: {sys.version}'); import customtkinter; print('CustomTkinter OK'); import cv2; print(f'OpenCV: {cv2.__version__}')"

Set-Location ..
Write-Host "`n Todos os testes passaram!" -ForegroundColor Green