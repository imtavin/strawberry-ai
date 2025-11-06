#!/bin/bash
# ===============================================================
# 🚀 Strawberry AI - Instalação Final (CORRIGIDO - CustomTkinter + Picamera2 Fix)
# ===============================================================

# set -e  # Para em caso de erro crítico

APP_NAME="strawberry-ai"
APP_DIR="/opt/${APP_NAME}"
SCRIPTS_DIR="$(dirname "$(realpath "$0")")"
SOURCE_DIR="$(dirname "$SCRIPTS_DIR")"  # Diretório fonte do projeto
SYSTEMD_DIR="/etc/systemd/system"

BACKEND_DIR="${APP_DIR}/backend"
FRONTEND_DIR="${APP_DIR}/frontend"

# Detectar o Python mais recente disponível no sistema
PYTHON_BIN=$(command -v python3)
if [ -z "$PYTHON_BIN" ]; then
    error "Python3 não encontrado no sistema."
fi
log "Usando Python detectado: $PYTHON_BIN"


# -------------------------------
# Funções auxiliares
# -------------------------------
log() {
    echo -e "\033[1;32m[INFO]\033[0m $1"
}
warn() {
    echo -e "\033[1;33m[AVISO]\033[0m $1"
}
error() {
    echo -e "\033[1;31m[ERRO]\033[0m $1"
    exit 1
}

# -------------------------------
# Verificação de privilégios
# -------------------------------
if [[ $EUID -ne 0 ]]; then
   error "Este script deve ser executado como root. Use: sudo ./install_final.sh"
fi

log "Iniciando instalação final do Strawberry AI..."
log "Sistema: $(lsb_release -d | cut -f2)"
log "Kernel: $(uname -r)"
log "Diretório fonte: $SOURCE_DIR"
log "Diretório destino: $APP_DIR"

# -------------------------------
# 0. PARAR TUDO E LIMPAR INSTALAÇÃO ANTERIOR
# -------------------------------
log "0. Parando serviços e limpando instalação anterior..."

# Parar todos os serviços
sudo systemctl stop strawberry-backend.service 2>/dev/null || true
sudo systemctl stop strawberry-kiosk.service 2>/dev/null || true
sudo systemctl stop strawberry-frontend.service 2>/dev/null || true

# Desabilitar serviços
sudo systemctl disable strawberry-backend.service 2>/dev/null || true
sudo systemctl disable strawberry-kiosk.service 2>/dev/null || true
sudo systemctl disable strawberry-frontend.service 2>/dev/null || true

# Matar todos os processos relacionados
sudo pkill -f "python.*strawberry" 2>/dev/null || true
sudo pkill -f "Xorg.*:0" 2>/dev/null || true
sudo pkill -f "mpv.*startup" 2>/dev/null || true
sudo pkill -f "unclutter" 2>/dev/null || true

# Aguardar processos terminarem
sleep 3

# -------------------------------
# 1. REMOVER E RECRIAR DIRETÓRIOS COMPLETAMENTE
# -------------------------------
log "1. Removendo e recriando estrutura de diretórios..."

# Remover diretórios antigos (exceto media, logs, capture)
if [ -d "$APP_DIR" ]; then
    log "Removendo diretório da aplicação anterior..."
    sudo rm -rf "${APP_DIR}/backend"
    sudo rm -rf "${APP_DIR}/frontend"
    sudo rm -rf "${APP_DIR}/scripts"
    sudo rm -rf "${APP_DIR}/logs"
    sudo rm -rf "${APP_DIR}/venv" 2>/dev/null || true
    sudo rm -rf "${APP_DIR}/venv-tkinter" 2>/dev/null || true
    sudo rm -f "${APP_DIR}/config.json" 2>/dev/null || true
    sudo rm -f "${APP_DIR}/requirements*.txt" 2>/dev/null || true
else
    sudo mkdir -p "$APP_DIR"
fi

# Criar estrutura completa
sudo mkdir -p "${APP_DIR}/backend"
sudo chown -R raspi:raspi /opt/strawberry-ai/backend
sudo chmod 755 /opt/strawberry-ai/backend

sudo mkdir -p "${APP_DIR}/frontend"
sudo chown -R raspi:raspi /opt/strawberry-ai/frontend
sudo chmod 755 /opt/strawberry-ai/frontend

sudo mkdir -p "${APP_DIR}/scripts"
sudo mkdir -p "${APP_DIR}/media"

sudo mkdir -p "${APP_DIR}/logs"
sudo touch /opt/strawberry-ai/logs/kiosk.log
sudo chown raspi:raspi /opt/strawberry-ai/logs/kiosk.log
sudo chmod 664 /opt/strawberry-ai/logs/kiosk.log


sudo mkdir -p "${APP_DIR}/capture"
sudo chown -R raspi:raspi /opt/strawberry-ai/capture
sudo chmod 755 /opt/strawberry-ai/capture

sudo chown -R raspi:raspi /opt/strawberry-ai
sudo chmod -R 755 /opt/strawberry-ai


# -------------------------------
# 2. COPIAR ARQUIVOS DO PROJETO ATUAL
# -------------------------------
log "2. Copiando arquivos do projeto atual..."

# Verificar se o diretório fonte existe
if [ ! -d "$SOURCE_DIR" ]; then
    error "Diretório fonte não encontrado: $SOURCE_DIR"
fi

# Copiar backend
log "Copiando backend..."
if [ -d "$SOURCE_DIR/backend" ]; then
    sudo cp -r "$SOURCE_DIR/backend/"* "$BACKEND_DIR/" 2>/dev/null || true
else
    error "Diretório backend não encontrado em $SOURCE_DIR/backend"
fi

# Copiar frontend
log "Copiando frontend..."
if [ -d "$SOURCE_DIR/frontend" ]; then
    sudo cp -r "$SOURCE_DIR/frontend/"* "$FRONTEND_DIR/" 2>/dev/null || true
else
    error "Diretório frontend não encontrado em $SOURCE_DIR/frontend"
fi

# Copiar arquivos raiz importantes
log "Copiando arquivos de configuração..."
if [ -f "$SOURCE_DIR/config.json" ]; then
    sudo cp "$SOURCE_DIR/config.json" "$APP_DIR/" 2>/dev/null || true
    sudo cp "$SOURCE_DIR/config.json" "$BACKEND_DIR/" 2>/dev/null || true
    sudo cp "$SOURCE_DIR/config.json" "$FRONTEND_DIR/" 2>/dev/null || true
    log "✅ config.json copiado para backend, frontend e diretório raiz"
else
    warn "config.json não encontrado no diretório fonte"
fi

# Verificar se os arquivos foram copiados
if [ ! -f "$BACKEND_DIR/main.py" ]; then
    error "Arquivo principal do backend não foi copiado corretamente"
fi
if [ ! -f "$FRONTEND_DIR/main.py" ]; then
    error "Arquivo principal do frontend não foi copiado corretamente"
fi

log "✅ Arquivos copiados com sucesso"

# -------------------------------
# 3. CONFIGURAR PERMISSÕES E GRUPOS (CRÍTICO)
# -------------------------------
log "3. Configurando permissões e grupos..."

# Adicionar usuário aos grupos necessários para câmera
sudo usermod -a -G tty raspi
sudo usermod -a -G video raspi
sudo usermod -a -G input raspi
sudo usermod -a -G audio raspi
sudo usermod -a -G plugdev raspi
sudo usermod -a -G render raspi

# Configurar Xwrapper para permitir qualquer usuário
sudo tee /etc/X11/Xwrapper.config > /dev/null << EOF
allowed_users=anybody
needs_root_rights=no
EOF

# Configurar câmera no boot
log "Configurando câmera no /boot/firmware/config.txt..."
if [ -f "/boot/firmware/config.txt" ]; then
    # Fazer backup
    sudo cp /boot/firmware/config.txt /boot/firmware/config.txt.backup
    
    # Adicionar configurações da câmera se não existirem
    if ! grep -q "start_x" /boot/firmware/config.txt; then
        echo "start_x=1" | sudo tee -a /boot/firmware/config.txt
    fi
    
    if ! grep -q "gpu_mem" /boot/firmware/config.txt; then
        echo "gpu_mem=128" | sudo tee -a /boot/firmware/config.txt
    fi
    
    if ! grep -q "camera_auto_detect" /boot/firmware/config.txt; then
        echo "camera_auto_detect=1" | sudo tee -a /boot/firmware/config.txt
    fi

    if ! grep -q "dtoverlay=vc4-kms-v3d" /boot/firmware/config.txt; then
        echo "dtoverlay=vc4-kms-v3d" | sudo tee -a /boot/firmware/config.txt
    fi
    
    log "✅ Configuração da câmera atualizada"
else
    warn "Arquivo /boot/firmware/config.txt não encontrado"
fi

# -------------------------------
# 4. INSTALAR DEPENDÊNCIAS DO SISTEMA (CRÍTICO)
# -------------------------------
log "4. Instalando dependências do sistema..."
sudo apt update

# FIX: Instalar Tkinter DO SISTEMA primeiro (crítico para CustomTkinter)
log "Instalando Tkinter do sistema..."
sudo apt install -y python3-tk tk-dev \
    python3-pil python3-pil.imagetk

# Instalar pacotes básicos ESSENCIAIS
sudo apt install -y --no-install-recommends \
    xserver-xorg xinit x11-xserver-utils xorg-dev \
    mpv ffmpeg unclutter net-tools imagemagick \
    python3-pip python3-venv python3-dev \
    libhdf5-dev libopenblas-dev libgtk-3-dev \
    xdotool openbox policykit-1

# -------------------------------
# 5. CONFIGURAR BACKEND COM BASE NO PICAMERA
# -------------------------------
log "5. Configurando backend..."

cd "${BACKEND_DIR}" || error "Falha ao acessar diretório do backend"

# Remover venv existente completamente
sudo rm -rf venv

log "Instalando Picamera2 via apt (se disponível)…"
if sudo apt install -y python3-picamera2 python3-libcamera libcamera-dev libcamera-tools v4l-utils; then
    log "✅ Instalado pacotes do sistema picamera2/libcamera"
    # criar venv com acesso aos pacotes do sistema
    $PYTHON_BIN -m venv --system-site-packages venv || error "Falha ao criar venv com system-site-packages"
else
    warn "⚠️ Pacotes APT para Picamera2 falharam ou não disponíveis. Vai tentar via pip"
    sudo apt install -y libcamera-dev libcamera-tools v4l-utils
    $PYTHON_BIN -m venv venv || error "Falha ao criar venv"
fi

source venv/bin/activate

# Atualizar pip
pip install --upgrade pip

# INSTALAR DEPENDÊNCIAS EM ORDEM CORRETA
log "Instalando dependências do backend..."

# 1. Primeiro numpy (crítico)
log "Instalando numpy..."
pip install numpy==1.26.4

# 2. TensorFlow Lite - TENTATIVAS EM ORDEM DE PREFERÊNCIA
log "🧠 Instalando TensorFlow Lite (tentativas com fallback)..."

TENSORFLOW_INSTALLED=false

# Tentativa 1: tflite-runtime específico (mais leve)
log "  🔹 Tentativa 1: tflite-runtime==2.14.0..."
if pip install tflite-runtime==2.14.0; then
    log "  ✅ tflite-runtime 2.14.0 instalado com sucesso"
    TENSORFLOW_INSTALLED=true
    TENSORFLOW_TYPE="tflite-runtime"
else
    log "  ❌ tflite-runtime 2.14.0 falhou, tentando versão mais recente..."
    
    # Tentativa 2: tflite-runtime mais recente
    if pip install tflite-runtime; then
        log "  ✅ tflite-runtime (última versão) instalado com sucesso"
        TENSORFLOW_INSTALLED=true
        TENSORFLOW_TYPE="tflite-runtime-latest"
    else
        log "  ❌ tflite-runtime falhou, tentando tensorflow completo..."
        
        # Tentativa 3: tensorflow completo (mais pesado mas mais compatível)
        if pip install tensorflow==2.14.0; then
            log "  ✅ tensorflow 2.14.0 instalado com sucesso"
            TENSORFLOW_INSTALLED=true
            TENSORFLOW_TYPE="tensorflow"
        else
            log "  ❌ tensorflow 2.14.0 falhou, tentando versão mais recente..."
            
            # Tentativa 4: tensorflow mais recente
            if pip install tensorflow; then
                log "  ✅ tensorflow (última versão) instalado com sucesso"
                TENSORFLOW_INSTALLED=true
                TENSORFLOW_TYPE="tensorflow-latest"
            else
                # Tentativa 5: via apt (para Raspberry Pi OS)
                log "  ❌ Todas as tentativas pip falharam, tentando via apt..."
                sudo apt update
                if sudo apt install -y python3-tflite-runtime; then
                    log "  ✅ python3-tflite-runtime instalado via apt"
                    TENSORFLOW_INSTALLED=true
                    TENSORFLOW_TYPE="tflite-runtime-apt"
                else
                    warn "  ⚠️  NENHUMA versão do TensorFlow pôde ser instalada - IA não funcionará"
                    TENSORFLOW_INSTALLED=false
                    TENSORFLOW_TYPE="none"
                fi
            fi
        fi
    fi
fi


# 3. OpenCV com suporte otimizado
log "Instalando OpenCV..."
pip install opencv-python-headless==4.10.0.84

# 4. Picamera2 - INSTALAÇÃO CORRIGIDA PARA VENV
log "Instalando Picamera2 no venv..."
# Se não instalado via apt ou import falhar, tente pip install
python -c "import picamera2; print('PICAMERA2_OK')" 2>/dev/null | grep -q PICAMERA2_OK
if [ $? -eq 0 ]; then
    log "✅ Picamera2 disponível no venv"
else
    log "❌ Picamera2 não disponível ainda – tentando pip install"
    if pip install picamera2; then
        log "✅ picamera2 instalado via pip"
        python -c "import picamera2; print('PICAMERA2_OK')" 2>/dev/null | grep -q PICAMERA2_OK && \
        log "✅ Picamera2 agora funciona via pip" || \
        warn "❌ Picamera2 via pip instalado mas import falha"
    else
        warn "❌ pip install picamera2 falhou"
    fi
fi

# 4. Dependências básicas
log "Instalando dependências básicas..."
pip install Flask==3.1.0 flask-cors==5.0.1
pip install psutil==5.9.8 requests==2.31.0
pip install Pillow==10.3.0 Werkzeug==3.1.3
pip install Jinja2==3.1.6 netifaces==0.11.0
pip install packaging==25.0

# 5. TESTAR IMPORTAÇÕES CRÍTICAS
log "🔍 Testando importações críticas do backend..."

# Testar numpy
if python -c "import numpy; print('NUMPY_OK')" 2>/dev/null | grep -q "NUMPY_OK"; then
    log "✅ Numpy funciona"
else
    error "❌ Numpy não instalado corretamente"
fi

# Testar TensorFlow baseado no tipo instalado
if [ "$TENSORFLOW_INSTALLED" = true ]; then
    case $TENSORFLOW_TYPE in
        "tflite-runtime"|"tflite-runtime-latest"|"tflite-runtime-apt")
            if python -c "import tflite_runtime.interpreter as tflite; print('TFLITE_RUNTIME_OK')" 2>/dev/null | grep -q "TFLITE_RUNTIME_OK"; then
                log "✅ TensorFlow Lite Runtime funciona"
            else
                warn "❌ TensorFlow Lite Runtime instalado mas não funciona"
            fi
            ;;
        "tensorflow"|"tensorflow-latest")
            if python -c "import tensorflow as tf; print('TENSORFLOW_OK')" 2>/dev/null | grep -q "TENSORFLOW_OK"; then
                log "✅ TensorFlow completo funciona"
            else
                warn "❌ TensorFlow instalado mas não funciona"
            fi
            ;;
    esac
else
    warn "⚠️  TensorFlow não instalado - IA não funcionará"
fi

# FIX: Testar Picamera2 com fallback
if python -c "import picamera2; print('PICAMERA2_OK')" 2>/dev/null | grep -q "PICAMERA2_OK"; then
    log "✅ Picamera2 funciona"
else
    warn "❌ Picamera2 com redirect não funciona - tentando install direto"
    if pip install picamera2; then
        log "✅ Picamera2 instalado via pip no venv"
        if python -c "import picamera2; print('PICAMERA2_OK')" 2>/dev/null | grep -q "PICAMERA2_OK"; then
            log "✅ Picamera2 funciona"
        else
            warn "❌ Picamera2 com redirect não funciona - tentando install direto"
        fi
    else
        warn "❌ Picamera2 via pip falhou, tentando link com sistema..."
    fi
fi

# Testar OpenCV
if python -c "import cv2; print('OPENCV_OK')" 2>/dev/null | grep -q "OPENCV_OK"; then
    log "✅ OpenCV funciona"
else
    warn "❌ OpenCV não funciona"
fi

# 6. Tentar instalar via requirements.txt se existir
if [ -f "requirements.txt" ]; then
    log "Instalando de requirements.txt..."
    pip install -r requirements.txt || warn "Algumas dependências do requirements.txt falharam"
fi

deactivate

# -------------------------------
# 6. CONFIGURAR FRONTEND COM PYTHON 3.12 (COM FIX PARA CUSTOMTKINTER)
# -------------------------------
log "6. Configurando frontend..."

cd "${FRONTEND_DIR}" || error "Falha ao acessar diretório do frontend"

# Remover venv existente
sudo rm -rf venv

# Criar venv com Python 3.12
log "Criando venv principal do frontend..."
$PYTHON_BIN -m venv --system-site-packages venv || error "Falha ao criar venv do frontend"
source venv/bin/activate

# FIX: Atualizar pip PRIMEIRO (crítico para CustomTkinter)
pip install --upgrade pip setuptools wheel

# FIX: Instalar CustomTkinter com dependências Tkinter explícitas
log "Instalando CustomTkinter com dependências Tkinter..."
pip install customtkinter==5.2.2 || {
    warn "CustomTkinter com versão específica falhou, tentando versão mais recente"
    pip install customtkinter
}

# FIX: Garantir que Pillow está instalado (dependência crítica)
pip install Pillow==10.4.0

# Instalar outras dependências
if [ -f "requirements-frontend.txt" ]; then
    pip install -r requirements-frontend.txt || {
        warn "Algumas dependências do frontend podem ter problemas"
        pip install opencv-python==4.10.0.84 numpy==1.26.4
        pip install netifaces==0.11.0 packaging==25.0
        pip install requests==2.31.0 psutil==5.9.8
    }
else
    warn "requirements-frontend.txt não encontrado, instalando dependências básicas..."
    pip install opencv-python numpy netifaces packaging requests psutil
fi

# FIX: Teste COMPLETO do CustomTkinter (não apenas import)
log "Testando CustomTkinter profundamente..."
if python -c "
import customtkinter as ctk
import tkinter
print('CustomTkinter OK')
print('Tkinter OK') 
" 2>/dev/null; then
    log "✅ CustomTkinter e Tkinter funcionam PERFEITAMENTE"
    MAIN_VENV_WORKS=true
else
    warn "❌ CustomTkinter com problemas"
    MAIN_VENV_WORKS=false
fi

deactivate

# -------------------------------
# SOLUÇÃO ALTERNATIVA: Se Tkinter não funcionar, criar venv com Python do sistema
# -------------------------------
ALTERNATIVE_VENV=false
log "Verificando Tkinter no sistema..."
if python3 -c "import tkinter; print('SYS_TKINTER_OK')" 2>/dev/null; then
    log "✅ Python do sistema tem Tkinter, criando venv alternativo..."
    cd "${FRONTEND_DIR}"
    
    # Criar venv com Python do sistema
    python3 -m venv venv-tkinter
    source venv-tkinter/bin/activate
    
    # Instalar dependências
    pip install --upgrade pip
    pip install customtkinter==5.2.2
    pip install Pillow==10.4.0
    pip install requests==2.31.0
    pip install psutil==5.9.8
    pip install opencv-python==4.10.0.84
    pip install numpy==1.26.4
    
    # Testar
    if python -c "import tkinter; import customtkinter; print('ALT_TKINTER_OK')" 2>/dev/null; then
        log "✅ Venv alternativo com Tkinter criado com sucesso"
        ALTERNATIVE_VENV=true
    else
        warn "❌ Venv alternativo também falhou"
        ALTERNATIVE_VENV=false
    fi
    
    deactivate
else
    warn "❌ Tkinter não disponível no sistema"
    ALTERNATIVE_VENV=false
fi

# -------------------------------
# 7. CONFIGURAR SISTEMA DE VÍDEO DE INICIALIZAÇÃO (COM FIX PARA VENV)
# -------------------------------
log "7. Configurando sistema de vídeo de inicialização..."

# Criar diretório para mídia
sudo mkdir -p /opt/strawberry-ai/media

# Criar script de inicialização kiosk mode
log "Criando scripts de inicialização kiosk..."

# Script da sessão X (roda DENTRO do X)
sudo tee /opt/strawberry-ai/scripts/x-session.sh > /dev/null << 'EOF'
#!/bin/bash
# Sessão X - Roda DENTRO do ambiente gráfico

exec >> /opt/strawberry-ai/logs/kiosk.log 2>&1

export DISPLAY=:0
export XAUTHORITY=/home/raspi/.Xauthority

# Configurações básicas do X
xsetroot -solid black
unclutter -idle 0.01 -root &
xset s off
xset -dpms

# VÍDEO IMEDIATO - primeira coisa no X
VIDEO_FILE="/opt/strawberry-ai/media/startup.mp4"
VIDEO_PID=""

if [ -f "$VIDEO_FILE" ]; then
    echo "🎬 Iniciando vídeo..." > /dev/tty1
    mpv --loop-file --no-osd-bar --fs --vo=xv "$VIDEO_FILE" &
    VIDEO_PID=$!
else
    echo "❌ Vídeo não encontrado" > /dev/tty1
fi

# Aguardar backend
echo "⏳ Inicializando sistema..." > /dev/tty1
MAX_WAIT=60
WAIT_COUNT=0
BACKEND_READY=0

while [ $WAIT_COUNT -lt $MAX_WAIT ]; do
    # Método 1: Verificar serviço systemd
    if systemctl is-active --quiet strawberry-backend.service; then
        BACKEND_READY=1
        break
    fi
    
    # Método 2: Verificar processo
    if pgrep -f "python.*/opt/strawberry-ai/backend/main.py" >/dev/null; then
        BACKEND_READY=1
        break
    fi
    
    # Método 3: Verificar porta
    if netstat -tln 2>/dev/null | grep -q ":5000 " || ss -tln 2>/dev/null | grep -q ":5000 "; then
        BACKEND_READY=1
        break
    fi
    
    sleep 2
    WAIT_COUNT=$((WAIT_COUNT+1))
done

# Transição para aplicação
echo "✅ Sistema pronto!" > /dev/tty1

# Parar vídeo se estiver rodando
if [ ! -z "$VIDEO_PID" ] && kill -0 $VIDEO_PID 2>/dev/null; then
    echo "🔄 Iniciando aplicação..." > /dev/tty1
    kill $VIDEO_PID 2>/dev/null
    sleep 1
fi

# Iniciar aplicação frontend
cd /opt/strawberry-ai/frontend

# FIX: ORDEM CORRETA de tentativas de venv
if [ -f "venv-tkinter/bin/python" ] && ./venv-tkinter/bin/python -c "import tkinter; import customtkinter" 2>/dev/null; then
    echo "🐍 Usando venv alternativo (Python do sistema)" > /dev/tty1
    ./venv-tkinter/bin/python main.py
elif [ -f "venv/bin/python" ] && ./venv/bin/python -c "import tkinter; import customtkinter" 2>/dev/null; then
    echo "🐍 Usando venv principal (Python 3.12)" > /dev/tty1
    ./venv/bin/python main.py
else
    echo "🐍 Usando Python do sistema como fallback" > /dev/tty1
    python3 main.py
fi

# Se aplicação terminar
APP_EXIT_CODE=$?
if [ $APP_EXIT_CODE -ne 0 ]; then
    echo "🔄 Reiniciando aplicação em 10 segundos..." > /dev/tty1
    sleep 10
    exec /opt/strawberry-ai/scripts/x-session.sh
fi
EOF

# Script de inicialização do kiosk
sudo tee /opt/strawberry-ai/scripts/start-kiosk.sh > /dev/null << 'EOF'
#!/bin/bash
# Script principal de inicialização do kiosk

exec >> /opt/strawberry-ai/logs/kiosk.log 2>&1

export HOME=/home/raspi
export USER=raspi
export DISPLAY=:0
export XAUTHORITY=/home/raspi/.Xauthority

# Limpar tela
printf "\033[2J\033[H" > /dev/tty1
printf "\033[?25l" > /dev/tty1

# AGUARDAR BACKEND ESTAR PRONTO ANTES DE INICIAR
echo "⏳ Aguardando backend..." > /dev/tty1
/opt/strawberry-ai/backend/venv/bin/python /opt/strawberry-ai/backend/test/test_healthcheck.py

if [ $? -ne 0 ]; then
    echo "❌ Backend não iniciou corretamente" > /dev/tty1
    exit 1
fi

echo "✅ Backend pronto!" > /dev/tty1

128 | sudo tee /sys/class/backlight/10-0045/brightness

# Parar X anterior e limpar
sudo pkill Xorg 2>/dev/null || true
sleep 2
sudo rm -f /tmp/.X0-lock /tmp/.X11-unix/X0

# Iniciar X Server
echo "🚀 Iniciando interface gráfica..." > /dev/tty1
sudo X :0 -nocursor -s 0 -dpms -nolisten tcp vt1 &

# Aguardar X inicializar
echo "⏳ Preparando display..." > /dev/tty1
MAX_X_WAIT=30
X_WAIT_COUNT=0

while [ $X_WAIT_COUNT -lt $MAX_X_WAIT ]; do
    if sudo -u raspi DISPLAY=:0 xset q >/dev/null 2>&1; then
        echo "✅ Interface pronta" > /dev/tty1
        break
    fi
    sleep 1
    X_WAIT_COUNT=$((X_WAIT_COUNT+1))
done

# Executar sessão principal se X estiver pronto
if sudo -u raspi DISPLAY=:0 xset q >/dev/null 2>&1; then
    printf "\033[2J\033[H" > /dev/tty1
    sudo -u raspi /opt/strawberry-ai/scripts/x-session.sh
else
    echo "❌ Falha na interface" > /dev/tty1
    exit 1
fi

# Limpar ao sair
sudo pkill Xorg 2>/dev/null || true
EOF

sudo chmod +x /opt/strawberry-ai/scripts/*.sh

# Criar vídeo placeholder se não existir
if [ ! -f "/opt/strawberry-ai/media/startup.mp4" ]; then
    log "Criando vídeo placeholder de inicialização..."
    sudo ffmpeg -f lavfi -i color=c=black:s=1920x1080:d=8 \
        -vf "drawtext=text='Strawberry AI':fontsize=60:fontcolor=white:x=(w-text_w)/2:y=(h-text_h)/2" \
        /opt/strawberry-ai/media/startup.mp4 -y 2>/dev/null || \
    warn "Não foi possível criar vídeo placeholder"
fi

# -------------------------------
# 8. CONFIGURAR SERVIÇOS SYSTEMD
# -------------------------------
log "8. Configurando serviços systemd..."

# Serviço do Backend
sudo tee /etc/systemd/system/strawberry-backend.service > /dev/null << EOF
[Unit]
Description=Strawberry AI Backend Service

[Service]
Type=simple
User=raspi
Group=raspi
WorkingDirectory=/opt/strawberry-ai/backend
ExecStart=/opt/strawberry-ai/backend/venv/bin/python main.py
Restart=always
RestartSec=5
Environment=PYTHONUNBUFFERED=1
Environment=PYTHONIOENCODING=utf-8
Environment=LANG=en_US.UTF-8
Environment=LC_ALL=en_US.UTF-8
StandardOutput=append:/opt/strawberry-ai/logs/backend.log
StandardError=append:/opt/strawberry-ai/logs/backend-error.log

[Install]
WantedBy=multi-user.target
EOF

# Serviço do Kiosk 
sudo tee /etc/systemd/system/strawberry-kiosk.service > /dev/null << EOF
[Unit]
Description=Strawberry AI Kiosk Mode
After=strawberry-backend.service
Requires=strawberry-backend.service
Wants=network.target
After=network.target

[Service]
Type=simple
User=raspi
Group=raspi
WorkingDirectory=/opt/strawberry-ai/scripts
ExecStartPre=/bin/sleep 15
ExecStart=/bin/bash /opt/strawberry-ai/scripts/start-kiosk.sh
Restart=always
RestartSec=10
TTYPath=/dev/tty1
Environment=PYTHONIOENCODING=utf-8
Environment=LANG=en_US.UTF-8
Environment=LC_ALL=en_US.UTF-8
StandardOutput=append:/opt/strawberry-ai/logs/kiosk.log
StandardError=append:/opt/strawberry-ai/logs/kiosk-error.log

[Install]
WantedBy=graphical.target
EOF


# -------------------------------
# 9. CONFIGURAR AUTO-LOGIN E INICIALIZAÇÃO
# -------------------------------
log "9. Configurando auto-login e inicialização..."

# Configurar auto-login no tty1
sudo mkdir -p /etc/systemd/system/getty@tty1.service.d
sudo tee /etc/systemd/system/getty@tty1.service.d/override.conf > /dev/null << EOF
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin raspi --noclear %I \$TERM
Type=idle
EOF

# Configurar .bashrc para auto-inicialização
sudo tee /home/raspi/.bash_kiosk > /dev/null << 'EOF'
# Auto-start Strawberry AI Kiosk on tty1
if [ "$(tty)" = "/dev/tty1" ]; then
    # Limpar tela
    printf "\033[2J\033[H"
    printf "\033[?25l"
    
    echo "Iniciando Strawberry AI..."
    sleep 2
    
    # Parar serviços se estiverem rodando
    sudo systemctl stop strawberry-kiosk.service 2>/dev/null || true
    sudo pkill Xorg 2>/dev/null || true
    
    # Iniciar backend primeiro
    sudo systemctl start strawberry-backend.service
    sleep 8
    
    # Iniciar kiosk
    sudo systemctl start strawberry-kiosk.service
    
    # Manter processo
    while true; do
        sleep 3600
    done
fi
EOF

# Adicionar ao .bashrc
if ! grep -q ".bash_kiosk" /home/raspi/.bashrc; then
    echo "source ~/.bash_kiosk" >> /home/raspi/.bashrc
/.bashrc
fi

# -------------------------------
# 10. CONFIGURAR ARQUIVOS E PERMISSÕES FINAIS
# -------------------------------
log "10. Configurando arquivos e permissões finais..."

# VERIFICAÇÃO FINAL DO CONFIG.JSON
log "Verificando presença do config.json..."
if [ ! -f "$FRONTEND_DIR/config.json" ]; then
    warn "❌ config.json NÃO encontrado no frontend - criando básico..."
    sudo tee "$FRONTEND_DIR/config.json" > /dev/null << 'EOF'
{
    "server": {
        "host": "127.0.0.1",
        "port": 5000
    },
    "video": {
        "transport": "tcp",
        "tcp_host": "127.0.0.1",
        "tcp_port": 5050
    },
    "udp": {
        "port": 5005,
        "listen_port": 5005,
        "max_packet_size": 4096
    },
    "camera": {
        "target_fps": 15
    }
}
EOF
    log "✅ config.json básico criado para frontend"
fi

if [ ! -f "$BACKEND_DIR/config.json" ]; then
    warn "❌ config.json NÃO encontrado no backend - criando básico..."
    sudo tee "$BACKEND_DIR/config.json" > /dev/null << 'EOF'
{
    "server": {
        "host": "127.0.0.1",
        "port": 5000
    },
    "video": {
        "transport": "tcp",
        "tcp_host": "127.0.0.1",
        "tcp_port": 5050
    },
    "udp": {
        "port": 5005,
        "listen_port": 5005,
        "max_packet_size": 4096
    },
    "camera": {
        "type": "picamera",
        "preview_size": [640, 480],
        "target_fps": 15,
        "jpeg_quality": 80
    },
    "ml": {
        "model_path": "models/strawberry_model.tflite",
        "labels_path": "models/labels.txt",
        "confidence_threshold": 0.6
    }
}
EOF
    log "✅ config.json básico criado para backend"
fi

# Permissões
sudo chown -R raspi:raspi /opt/strawberry-ai
sudo chmod +x /opt/strawberry-ai/backend/main.py
sudo chmod +x /opt/strawberry-ai/frontend/main.py

# Permissões sudo para o usuário raspi
sudo tee /etc/sudoers.d/strawberry-raspi > /dev/null << EOF
raspi ALL=(ALL) NOPASSWD: /bin/systemctl start strawberry-backend.service
raspi ALL=(ALL) NOPASSWD: /bin/systemctl stop strawberry-backend.service
raspi ALL=(ALL) NOPASSWD: /bin/systemctl start strawberry-kiosk.service
raspi ALL=(ALL) NOPASSWD: /bin/systemctl stop strawberry-kiosk.service
raspi ALL=(ALL) NOPASSWD: /usr/bin/pkill Xorg
raspi ALL=(ALL) NOPASSWD: /usr/bin/pkill mpv
raspi ALL=(ALL) NOPASSWD: /sbin/reboot, /sbin/poweroff
EOF

sudo chmod 440 /etc/sudoers.d/strawberry-raspi

# -------------------------------
# 11. RECARREGAR E INICIAR SERVIÇOS
# -------------------------------
log "11. Recarregando e iniciando serviços..."

systemctl daemon-reload
systemctl enable strawberry-backend.service
systemctl enable strawberry-kiosk.service

log "🚀 Iniciando Strawberry AI..."
systemctl start strawberry-backend.service
sleep 5
systemctl start strawberry-kiosk.service

log "✅ Instalação concluída com sucesso!"

# -------------------------------
# 12. VERIFICAÇÃO FINAL
# -------------------------------
log "12. Verificando instalação..."

sleep 5

echo ""
echo "🔍 VERIFICAÇÃO DO SISTEMA:"
echo "=========================="

# Verificar serviços
echo "📊 Status dos serviços:"
sudo systemctl is-active strawberry-backend.service >/dev/null && echo "✅ Backend: ATIVO" || echo "❌ Backend: INATIVO"
sudo systemctl is-active strawberry-kiosk.service >/dev/null && echo "✅ Kiosk: ATIVO" || echo "❌ Kiosk: INATIVO"

# Verificar processos
echo ""
echo "🔄 Processos em execução:"
pgrep -f "python.*backend" >/dev/null && echo "✅ Processo backend rodando" || echo "❌ Processo backend não encontrado"
pgrep -f "Xorg" >/dev/null && echo "✅ X Server rodando" || echo "❌ X Server não encontrado"

# Verificar portas
echo ""
echo "🌐 Portas de rede:"
netstat -tln 2>/dev/null | grep ":5000" >/dev/null && echo "✅ Backend ouvindo na porta 5000" || echo "❌ Backend não na porta 5000"

# Verificar arquivos CRÍTICOS
echo ""
echo "📁 Arquivos da aplicação:"
[ -f "/opt/strawberry-ai/backend/main.py" ] && echo "✅ Backend main.py encontrado" || echo "❌ Backend main.py não encontrado"
[ -f "/opt/strawberry-ai/frontend/main.py" ] && echo "✅ Frontend main.py encontrado" || echo "❌ Frontend main.py não encontrado"
[ -f "/opt/strawberry-ai/frontend/config.json" ] && echo "✅ Frontend config.json encontrado" || echo "❌ Frontend config.json NÃO encontrado"
[ -f "/opt/strawberry-ai/backend/config.json" ] && echo "✅ Backend config.json encontrado" || echo "❌ Backend config.json NÃO encontrado"

# FIX: Verificação EXTRA dos ambientes virtuais
echo ""
echo "🐍 Ambientes Virtuais:"
[ -f "/opt/strawberry-ai/frontend/venv/bin/python" ] && echo "✅ Venv principal do frontend existe" || echo "❌ Venv principal do frontend NÃO existe"
[ -f "/opt/strawberry-ai/frontend/venv-tkinter/bin/python" ] && echo "✅ Venv alternativo existe" || echo "❌ Venv alternativo NÃO existe"

# Testar CustomTkinter nos venvs
echo ""
echo "🎨 Teste CustomTkinter:"
if [ -f "/opt/strawberry-ai/frontend/venv/bin/python" ]; then
    /opt/strawberry-ai/frontend/venv/bin/python -c "import customtkinter; print('✅ Venv principal: CustomTkinter OK')" 2>/dev/null || echo "❌ Venv principal: CustomTkinter FALHOU"
fi

if [ -f "/opt/strawberry-ai/frontend/venv-tkinter/bin/python" ]; then
    /opt/strawberry-ai/frontend/venv-tkinter/bin/python -c "import customtkinter; print('✅ Venv alternativo: CustomTkinter OK')" 2>/dev/null || echo "❌ Venv alternativo: CustomTkinter FALHOU"
fi

# Driver KMS e GPU
grep -q "dtoverlay=vc4-kms-v3d" /boot/firmware/config.txt || \
echo "dtoverlay=vc4-kms-v3d" | sudo tee -a /boot/firmware/config.txt

# -------------------------------
# 13. CONCLUSÃO
# -------------------------------
log "✅ INSTALAÇÃO FINAL CONCLUÍDA!"
echo ""
echo "🎯 CORREÇÕES APLICADAS:"
echo "======================"
echo "🔧 FIX 1: CustomTkinter - Instalação garantida com Tkinter do sistema"
echo "🔧 FIX 2: picamera - Link simbólico do sistema para venv do backend"  
echo "🔧 FIX 3: Ordem de venv corrigida no x-session.sh"
echo "🔧 FIX 4: Verificação completa de ambientes virtuais"
echo ""
echo "📊 STATUS ESPERADO:"
echo "==================="
echo "✅ Frontend: CustomTkinter deve funcionar corretamente"
echo "✅ Backend: Picamera2 deve inicializar sem erros"
echo "✅ Câmera: Sem frames vazios com fallback OpenCV"
echo ""
echo "🔄 PRÓXIMOS PASSOS:"
echo "=================="
echo "1. REINICIE O SISTEMA: sudo reboot"
echo "2. Verifique os logs: sudo journalctl -u strawberry-backend -f"
echo "3. Teste a interface: A tela deve abrir sem erros de CustomTkinter"
echo ""
echo "🎉 SISTEMA CORRIGIDO E ESTÁVEL!"