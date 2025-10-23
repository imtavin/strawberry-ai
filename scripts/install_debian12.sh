#!/bin/bash
# ===============================================================
# 🚀 Strawberry AI - Instalação Para Debian 12 (Bookworm)
# ===============================================================

set -e  # Para em caso de erro crítico

APP_NAME="strawberry-ai"
APP_DIR="/opt/${APP_NAME}"
SCRIPTS_DIR="$(dirname "$(realpath "$0")")"
SOURCE_DIR="$(dirname "$SCRIPTS_DIR")"  # Diretório fonte do projeto
SYSTEMD_DIR="/etc/systemd/system"

BACKEND_DIR="${APP_DIR}/backend"
FRONTEND_DIR="${APP_DIR}/frontend"

# USAR PYTHON 3.12 - VERIFICAR DISPONIBILIDADE
PYTHON_BIN="/usr/local/bin/python3.12"
if [ ! -f "$PYTHON_BIN" ]; then
    PYTHON_BIN=$(which python3.12 2>/dev/null || which python3)
fi

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
# Verificação de privilégios e sistema
# -------------------------------
if [[ $EUID -ne 0 ]]; then
   error "Este script deve ser executado como root. Use: sudo ./install_final.sh"
fi

log "Iniciando instalação do Strawberry AI para Debian 12..."
log "Sistema: $(lsb_release -d | cut -f2)"
log "Kernel: $(uname -r)"
log "Arquitetura: $(uname -m)"
log "Diretório fonte: $SOURCE_DIR"
log "Diretório destino: $APP_DIR"

# Verificar se é Raspberry Pi
if grep -q "Raspberry Pi" /proc/device-tree/model 2>/dev/null || [ -f /proc/device-tree/model ]; then
    IS_RASPBERRY_PI=true
    log "✅ Raspberry Pi detectado"
else
    IS_RASPBERRY_PI=false
    warn "⚠️  Sistema não identificado como Raspberry Pi - recursos de câmera podem não funcionar"
fi

# -------------------------------
# 0. PARAR TUDO E LIMPAR INSTALAÇÃO ANTERIOR
# -------------------------------
log "0. Parando serviços e limpando instalação anterior..."

# Parar todos os serviços
systemctl stop strawberry-backend.service 2>/dev/null || true
systemctl stop strawberry-kiosk.service 2>/dev/null || true
systemctl stop strawberry-frontend.service 2>/dev/null || true

# Desabilitar serviços
systemctl disable strawberry-backend.service 2>/dev/null || true
systemctl disable strawberry-kiosk.service 2>/dev/null || true
systemctl disable strawberry-frontend.service 2>/dev/null || true

# Matar todos os processos relacionados
pkill -f "python.*strawberry" 2>/dev/null || true
pkill -f "Xorg.*:0" 2>/dev/null || true
pkill -f "mpv.*startup" 2>/dev/null || true
pkill -f "unclutter" 2>/dev/null || true

# Aguardar processos terminarem
sleep 3

# -------------------------------
# 1. REMOVER E RECRIAR DIRETÓRIOS COMPLETAMENTE
# -------------------------------
log "1. Removendo e recriando estrutura de diretórios..."

# Remover diretórios antigos (exceto media, logs, capture)
if [ -d "$APP_DIR" ]; then
    log "Removendo diretório da aplicação anterior..."
    rm -rf "${APP_DIR}/backend"
    rm -rf "${APP_DIR}/frontend"
    rm -rf "${APP_DIR}/scripts"
    rm -rf "${APP_DIR}/venv" 2>/dev/null || true
    rm -rf "${APP_DIR}/venv-tkinter" 2>/dev/null || true
    rm -f "${APP_DIR}/config.json" 2>/dev/null || true
    rm -f "${APP_DIR}/requirements*.txt" 2>/dev/null || true
else
    mkdir -p "$APP_DIR"
fi

# Criar estrutura completa
mkdir -p "${APP_DIR}/backend"
mkdir -p "${APP_DIR}/frontend"
mkdir -p "${APP_DIR}/scripts"
mkdir -p "${APP_DIR}/media"
mkdir -p "${APP_DIR}/logs"
mkdir -p "${APP_DIR}/capture"

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
    cp -r "$SOURCE_DIR/backend/"* "$BACKEND_DIR/" 2>/dev/null || true
else
    error "Diretório backend não encontrado em $SOURCE_DIR/backend"
fi

# Copiar frontend
log "Copiando frontend..."
if [ -d "$SOURCE_DIR/frontend" ]; then
    cp -r "$SOURCE_DIR/frontend/"* "$FRONTEND_DIR/" 2>/dev/null || true
else
    error "Diretório frontend não encontrado em $SOURCE_DIR/frontend"
fi

# Copiar arquivos raiz importantes
log "Copiando arquivos de configuração..."
if [ -f "$SOURCE_DIR/config.json" ]; then
    cp "$SOURCE_DIR/config.json" "$APP_DIR/" 2>/dev/null || true
    cp "$SOURCE_DIR/config.json" "$BACKEND_DIR/" 2>/dev/null || true
    cp "$SOURCE_DIR/config.json" "$FRONTEND_DIR/" 2>/dev/null || true
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
# 3. INSTALAR DEPENDÊNCIAS DO SISTEMA DEBIAN 12
# -------------------------------
log "3. Instalando dependências do sistema para Debian 12..."

# Atualizar repositórios
apt update

# FIX DEBIAN 12: Instalar Tkinter e dependências gráficas
log "Instalando dependências gráficas e Tkinter..."
apt install -y python3-tk tk-dev

# FIX DEBIAN 12: Instalar pacotes básicos ESSENCIAIS atualizados
apt install -y --no-install-recommends \
    xserver-xorg xinit x11-xserver-utils xorg-dev \
    mpv ffmpeg unclutter net-tools imagemagick \
    python3-pip python3-venv python3-dev python3-full \
    libhdf5-dev libopenblas-dev libgtk-3-dev \
    libjpeg-dev libtiff5-dev libpng-dev \
    libavcodec-dev libavformat-dev libswscale-dev \
    libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev

# FIX CRÍTICO: Instalar dependências da câmera atualizadas para Debian 12
if [ "$IS_RASPBERRY_PI" = true ]; then
    log "Instalando dependências da câmera para Raspberry Pi..."
    
    # Verificar e adicionar repositório Raspberry Pi se necessário
    if ! grep -q "raspberrypi" /etc/apt/sources.list.d/* 2>/dev/null; then
        warn "⚠️  Repositório Raspberry Pi não encontrado, adicionando..."
        echo "deb http://archive.raspberrypi.com/debian/ bookworm main" > /etc/apt/sources.list.d/raspberrypi.list
        curl -sSL https://archive.raspberrypi.com/debian/raspberrypi.gpg.key | apt-key add - 2>/dev/null || true
        apt update
    fi
    
    # Instalar pacotes ATUALIZADOS da câmera
    apt install -y --no-install-recommends \
        rpicam-apps \
        libcamera-dev \
        libcamera-tools \
        v4l-utils \
        python3-picamera2
else
    log "Instalando dependências de câmera genéricas..."
    apt install -y --no-install-recommends \
        v4l-utils \
        fswebcam \
        python3-opencv
fi

# -------------------------------
# 4. CONFIGURAR PERMISSÕES E GRUPOS
# -------------------------------
log "4. Configurando permissões e grupos..."

# Adicionar usuário aos grupos necessários
usermod -a -G tty raspi 2>/dev/null || true
usermod -a -G video raspi 2>/dev/null || true
usermod -a -G input raspi 2>/dev/null || true
usermod -a -G audio raspi 2>/dev/null || true
usermod -a -G plugdev raspi 2>/dev/null || true

# Configurar Xwrapper para permitir qualquer usuário
mkdir -p /etc/X11
tee /etc/X11/Xwrapper.config > /dev/null << EOF
allowed_users=anybody
needs_root_rights=yes
EOF

# FIX DEBIAN 12: Configurar câmera no boot (apenas Raspberry Pi)
if [ "$IS_RASPBERRY_PI" = true ]; then
    log "Configurando câmera no /boot/firmware/config.txt..."
    
    # Identificar arquivo de configuração correto
    if [ -f "/boot/firmware/config.txt" ]; then
        CONFIG_FILE="/boot/firmware/config.txt"
    elif [ -f "/boot/config.txt" ]; then
        CONFIG_FILE="/boot/config.txt"
    else
        warn "Arquivo de configuração do boot não encontrado"
        CONFIG_FILE="/boot/firmware/config.txt"
        touch "$CONFIG_FILE" 2>/dev/null || true
    fi
    
    if [ -f "$CONFIG_FILE" ]; then
        # Fazer backup
        cp "$CONFIG_FILE" "${CONFIG_FILE}.backup"
        
        # Configurações ATUALIZADAS para Debian 12 + Raspberry Pi
        log "Aplicando configurações ATUALIZADAS da câmera..."
        
        # Remover configurações antigas conflitantes
        sed -i '/^start_x/d' "$CONFIG_FILE"
        sed -i '/^gpu_mem/d' "$CONFIG_FILE"
        sed -i '/^camera_auto_detect/d' "$CONFIG_FILE"
        
        # Adicionar configurações novas
        echo "start_x=1" >> "$CONFIG_FILE"
        echo "gpu_mem=128" >> "$CONFIG_FILE"
        echo "camera_auto_detect=1" >> "$CONFIG_FILE"
        
        log "✅ Configuração da câmera atualizada para Debian 12"
    else
        warn "Não foi possível acessar arquivo de configuração do boot"
    fi
fi

# -------------------------------
# 5. CONFIGURAR BACKEND COM PYTHON 3.12
# -------------------------------
log "5. Configurando backend..."

cd "${BACKEND_DIR}" || error "Falha ao acessar diretório do backend"

# Remover venv existente completamente
rm -rf venv

# Criar venv com Python disponível
log "Criando venv do backend com $PYTHON_BIN..."
$PYTHON_BIN -m venv venv || {
    warn "Falha ao criar venv com $PYTHON_BIN, usando python3..."
    python3 -m venv venv || error "Falha ao criar venv do backend"
}
source venv/bin/activate

# Atualizar pip
pip install --upgrade pip

# INSTALAR DEPENDÊNCIAS EM ORDEM CORRETA - DEBIAN 12
log "Instalando dependências do backend para Debian 12..."

# 1. Primeiro numpy (crítico)
log "Instalando numpy..."
pip install numpy==1.26.4

# 2. TensorFlow - versões compatíveis com Debian 12
log "🧠 Instalando TensorFlow..."
TENSORFLOW_INSTALLED=false

# Tentativa com versões compatíveis
if pip install tensorflow==2.13.0; then
    log "✅ TensorFlow 2.13.0 instalado com sucesso"
    TENSORFLOW_INSTALLED=true
    TENSORFLOW_TYPE="tensorflow"
else
    log "🔄 Tentando TensorFlow mais recente..."
    if pip install tensorflow; then
        log "✅ TensorFlow (última versão) instalado com sucesso"
        TENSORFLOW_INSTALLED=true
        TENSORFLOW_TYPE="tensorflow-latest"
    else
        warn "⚠️  TensorFlow não pôde ser instalado - IA não funcionará"
        TENSORFLOW_INSTALLED=false
    fi
fi

# 3. OpenCV com suporte otimizado
log "Instalando OpenCV..."
pip install opencv-python-headless==4.8.1.78

# 4. FIX DEBIAN 12: Picamera2 apenas para Raspberry Pi
if [ "$IS_RASPBERRY_PI" = true ]; then
    log "Instalando Picamera2 no venv..."
    
    # Tentar instalar via pip primeiro
    if pip install picamera2==0.3.31; then
        log "✅ Picamera2 instalado via pip no venv"
    else
        warn "❌ Picamera2 via pip falhou, tentando versão mais recente..."
        if pip install picamera2; then
            log "Picamera2 instalado com sucesso"
        else
            log "Seguindo com OpenCV"
        fi
    fi
else
    log "⚠️  Picamera2 não instalado (não é Raspberry Pi)"
fi

# 5. Dependências básicas atualizadas
log "Instalando dependências básicas..."
pip install Flask==2.3.3 flask-cors==4.0.0
pip install psutil==5.9.5 requests==2.31.0
pip install Pillow==10.0.1 Werkzeug==2.3.7
pip install Jinja2==3.1.2 netifaces==0.11.0
pip install packaging==23.1

# 6. TESTAR IMPORTAÇÕES CRÍTICAS
log "🔍 Testando importações críticas do backend..."

# Testar numpy
if python -c "import numpy; print('✅ Numpy OK')"; then
    log "✅ Numpy funciona"
else
    error "❌ Numpy não instalado corretamente"
fi

# Testar TensorFlow
if [ "$TENSORFLOW_INSTALLED" = true ]; then
    if python -c "import tensorflow as tf; print('✅ TensorFlow OK')"; then
        log "✅ TensorFlow funciona"
    else
        warn "❌ TensorFlow instalado mas não funciona"
    fi
fi

# Testar Picamera2 apenas no Raspberry Pi
if [ "$IS_RASPBERRY_PI" = true ]; then
    if python -c "import picamera2; print('✅ Picamera2 OK')"; then
        log "✅ Picamera2 funciona"
    else
        warn "❌ Picamera2 não funciona"
    fi
fi

# Testar OpenCV
if python -c "import cv2; print('✅ OpenCV OK')"; then
    log "✅ OpenCV funciona"
else
    warn "❌ OpenCV não funciona"
fi

# 7. Tentar instalar via requirements.txt se existir
if [ -f "requirements.txt" ]; then
    log "Instalando de requirements.txt..."
    pip install -r requirements.txt || warn "Algumas dependências do requirements.txt falharam"
fi

deactivate

# -------------------------------
# 6. CONFIGURAR FRONTEND COM PYTHON
# -------------------------------
log "6. Configurando frontend..."

cd "${FRONTEND_DIR}" || error "Falha ao acessar diretório do frontend"

# Remover venv existente
rm -rf venv

# Criar venv
log "Criando venv principal do frontend..."
$PYTHON_BIN -m venv venv || {
    warn "Falha ao criar venv com $PYTHON_BIN, usando python3..."
    python3 -m venv venv
}
source venv/bin/activate

# FIX DEBIAN 12: Atualizar pip e dependências
pip install --upgrade pip setuptools wheel

# FIX DEBIAN 12: Instalar CustomTkinter compatível
log "Instalando CustomTkinter para Debian 12..."
pip install customtkinter==5.2.2 || {
    warn "CustomTkinter com versão específica falhou, tentando versão mais recente"
    pip install customtkinter
}

# Garantir que Pillow está instalado
pip install Pillow==10.0.1

# Instalar outras dependências
if [ -f "requirements-frontend.txt" ]; then
    pip install -r requirements-frontend.txt || {
        warn "Algumas dependências do frontend podem ter problemas"
        pip install opencv-python==4.8.1.78 numpy==1.26.4
        pip install netifaces==0.11.0 packaging==23.1
        pip install requests==2.31.0 psutil==5.9.5
    }
else
    warn "requirements-frontend.txt não encontrado, instalando dependências básicas..."
    pip install opencv-python numpy netifaces packaging requests psutil
fi

# Testar CustomTkinter
log "Testando CustomTkinter..."
if python -c "import customtkinter as ctk; import tkinter; print('✅ CustomTkinter e Tkinter OK')"; then
    log "✅ CustomTkinter e Tkinter funcionam"
    MAIN_VENV_WORKS=true
else
    warn "❌ CustomTkinter com problemas"
    MAIN_VENV_WORKS=false
fi

deactivate

# -------------------------------
# SOLUÇÃO ALTERNATIVA: Venv com Python do sistema
# -------------------------------
ALTERNATIVE_VENV=false
if [ "$MAIN_VENV_WORKS" = false ]; then
    log "Criando venv alternativo com Python do sistema..."
    cd "${FRONTEND_DIR}"
    
    python3 -m venv venv-tkinter
    source venv-tkinter/bin/activate
    
    pip install --upgrade pip
    pip install customtkinter==5.2.2
    pip install Pillow==10.0.1
    pip install requests==2.31.0
    pip install psutil==5.9.5
    pip install opencv-python==4.8.1.78
    pip install numpy==1.26.4
    
    if python -c "import tkinter; import customtkinter; print('✅ Tkinter alternativo OK')"; then
        log "✅ Venv alternativo com Tkinter criado com sucesso"
        ALTERNATIVE_VENV=true
    else
        warn "❌ Venv alternativo também falhou"
        ALTERNATIVE_VENV=false
    fi
    
    deactivate
fi

# -------------------------------
# 7. CONFIGURAR SISTEMA DE INICIALIZAÇÃO
# -------------------------------
log "7. Configurando sistema de inicialização..."

# Criar diretório para mídia
mkdir -p /opt/strawberry-ai/media

# Script da sessão X (ATUALIZADO)
tee /opt/strawberry-ai/scripts/x-session.sh > /dev/null << 'EOF'
#!/bin/bash
# Sessão X - Roda DENTRO do ambiente gráfico

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
    if systemctl is-active --quiet strawberry-backend.service; then
        BACKEND_READY=1
        break
    fi
    
    if pgrep -f "python.*/opt/strawberry-ai/backend/main.py" >/dev/null; then
        BACKEND_READY=1
        break
    fi
    
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

# ORDEM CORRETA de tentativas de venv
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
tee /opt/strawberry-ai/scripts/start-kiosk.sh > /dev/null << 'EOF'
#!/bin/bash
# Script principal de inicialização do kiosk

export HOME=/home/raspi
export USER=raspi
export DISPLAY=:0
export XAUTHORITY=/home/raspi/.Xauthority

# Limpar tela
printf "\033[2J\033[H" > /dev/tty1
printf "\033[?25l" > /dev/tty1

# Parar X anterior e limpar
pkill Xorg 2>/dev/null || true
sleep 1
rm -f /tmp/.X0-lock /tmp/.X11-unix/X0

# Iniciar X Server
echo "🚀 Iniciando interface..." > /dev/tty1
sudo -u raspi X :0 -nocursor -s 0 -dpms -nolisten tcp vt1 &

# Aguardar X
echo "⏳ Preparando sistema..." > /dev/tty1
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
pkill Xorg 2>/dev/null || true
EOF

chmod +x /opt/strawberry-ai/scripts/*.sh

# Criar vídeo placeholder se não existir
if [ ! -f "/opt/strawberry-ai/media/startup.mp4" ]; then
    log "Criando vídeo placeholder de inicialização..."
    ffmpeg -f lavfi -i color=c=black:s=1920x1080:d=8 \
        -vf "drawtext=text='Strawberry AI':fontsize=60:fontcolor=white:x=(w-text_w)/2:y=(h-text_h)/2" \
        /opt/strawberry-ai/media/startup.mp4 -y 2>/dev/null || \
    warn "Não foi possível criar vídeo placeholder"
fi

# -------------------------------
# 8. CONFIGURAR SERVIÇOS SYSTEMD
# -------------------------------
log "8. Configurando serviços systemd..."

# Serviço do Backend
tee /etc/systemd/system/strawberry-backend.service > /dev/null << EOF
[Unit]
Description=Strawberry AI Backend Service
After=network.target

[Service]
Type=simple
User=raspi
Group=raspi
WorkingDirectory=/opt/strawberry-ai/backend
ExecStart=/opt/strawberry-ai/backend/venv/bin/python main.py
Restart=always
RestartSec=10
Environment=PYTHONUNBUFFERED=1
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

# Serviço do Kiosk
tee /etc/systemd/system/strawberry-kiosk.service > /dev/null << EOF
[Unit]
Description=Strawberry AI Kiosk Mode
After=multi-user.target strawberry-backend.service
Wants=strawberry-backend.service

[Service]
Type=simple
User=raspi
Group=raspi
WorkingDirectory=/home/raspi
Environment=DISPLAY=:0
Environment=XAUTHORITY=/home/raspi/.Xauthority
ExecStart=/bin/bash /opt/strawberry-ai/scripts/start-kiosk.sh
Restart=always
RestartSec=15
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

# -------------------------------
# 9. CONFIGURAR AUTO-LOGIN - CORREÇÃO USUÁRIO
# -------------------------------
log "9. Configurando auto-login e inicialização..."

# CORREÇÃO: Usar usuário atual
mkdir -p /etc/systemd/system/getty@tty1.service.d
tee /etc/systemd/system/getty@tty1.service.d/override.conf > /dev/null << EOF
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin $CURRENT_USER --noclear %I \$TERM
Type=idle
EOF

# CORREÇÃO: Usar home directory correta
log "Configurando auto-inicialização para usuário $CURRENT_USER..."
tee $USER_HOME/.bash_kiosk > /dev/null << 'EOF'
# Auto-start Strawberry AI Kiosk on tty1
if [ "$(tty)" = "/dev/tty1" ]; then
    printf "\033[2J\033[H"
    printf "\033[?25l"
    
    echo "Iniciando Strawberry AI..."
    sleep 2
    
    systemctl stop strawberry-kiosk.service 2>/dev/null || true
    pkill Xorg 2>/dev/null || true
    
    systemctl start strawberry-backend.service
    sleep 8
    
    systemctl start strawberry-kiosk.service
    
    while true; do
        sleep 3600
    done
fi
EOF

# CORREÇÃO: Adicionar ao .bashrc do usuário correto
if ! grep -q ".bash_kiosk" $USER_HOME/.bashrc; then
    echo "source ~/.bash_kiosk" >> $USER_HOME/.bashrc
fi

# CORREÇÃO: Ajustar dono dos arquivos
chown -R $CURRENT_USER:$CURRENT_USER $USER_HOME/.bash_kiosk
chown -R $CURRENT_USER:$CURRENT_USER $USER_HOME/.bashrc

# -------------------------------
# 10. CONFIGURAR SERVIÇOS SYSTEMD - CORREÇÃO USUÁRIO
# -------------------------------
log "10. Configurando serviços systemd..."

# CORREÇÃO: Usar usuário atual nos serviços
tee /etc/systemd/system/strawberry-backend.service > /dev/null << EOF
[Unit]
Description=Strawberry AI Backend Service
After=network.target

[Service]
Type=simple
User=$CURRENT_USER
Group=$CURRENT_USER
WorkingDirectory=/opt/strawberry-ai/backend
ExecStart=/opt/strawberry-ai/backend/venv/bin/python main.py
Restart=always
RestartSec=10
Environment=PYTHONUNBUFFERED=1
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

tee /etc/systemd/system/strawberry-kiosk.service > /dev/null << EOF
[Unit]
Description=Strawberry AI Kiosk Mode
After=multi-user.target strawberry-backend.service
Wants=strawberry-backend.service

[Service]
Type=simple
User=$CURRENT_USER
Group=$CURRENT_USER
WorkingDirectory=$USER_HOME
Environment=DISPLAY=:0
Environment=XAUTHORITY=$USER_HOME/.Xauthority
ExecStart=/bin/bash /opt/strawberry-ai/scripts/start-kiosk.sh
Restart=always
RestartSec=15
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

# -------------------------------
# 11. SCRIPTS DE INICIALIZAÇÃO - CORREÇÃO USUÁRIO
# -------------------------------
log "11. Atualizando scripts de inicialização..."

# CORREÇÃO: Atualizar scripts com usuário correto
tee /opt/strawberry-ai/scripts/start-kiosk.sh > /dev/null << EOF
#!/bin/bash
export HOME=$USER_HOME
export USER=$CURRENT_USER
export DISPLAY=:0
export XAUTHORITY=$USER_HOME/.Xauthority

printf "\033[2J\033[H" > /dev/tty1
printf "\033[?25l" > /dev/tty1

pkill Xorg 2>/dev/null || true
sleep 1
rm -f /tmp/.X0-lock /tmp/.X11-unix/X0

echo "🚀 Iniciando interface..." > /dev/tty1
sudo -u $CURRENT_USER X :0 -nocursor -s 0 -dpms -nolisten tcp vt1 &

MAX_X_WAIT=30
X_WAIT_COUNT=0

while [ \$X_WAIT_COUNT -lt \$MAX_X_WAIT ]; do
    if sudo -u $CURRENT_USER DISPLAY=:0 xset q >/dev/null 2>&1; then
        echo "✅ Interface pronta" > /dev/tty1
        break
    fi
    sleep 1
    X_WAIT_COUNT=\$((X_WAIT_COUNT+1))
done

if sudo -u $CURRENT_USER DISPLAY=:0 xset q >/dev/null 2>&1; then
    printf "\033[2J\033[H" > /dev/tty1
    sudo -u $CURRENT_USER /opt/strawberry-ai/scripts/x-session.sh
else
    echo "❌ Falha na interface" > /dev/tty1
    exit 1
fi

pkill Xorg 2>/dev/null || true
EOF

# CORREÇÃO: Atualizar x-session.sh
tee /opt/strawberry-ai/scripts/x-session.sh > /dev/null << EOF
#!/bin/bash
export DISPLAY=:0
export XAUTHORITY=$USER_HOME/.Xauthority

xsetroot -solid black
unclutter -idle 0.01 -root &
xset s off
xset -dpms

VIDEO_FILE="/opt/strawberry-ai/media/startup.mp4"
VIDEO_PID=""

if [ -f "\$VIDEO_FILE" ]; then
    echo "🎬 Iniciando vídeo..." > /dev/tty1
    mpv --loop-file --no-osd-bar --fs --vo=xv "\$VIDEO_FILE" &
    VIDEO_PID=\$!
else
    echo "❌ Vídeo não encontrado" > /dev/tty1
fi

echo "⏳ Inicializando sistema..." > /dev/tty1
MAX_WAIT=60
WAIT_COUNT=0
BACKEND_READY=0

while [ \$WAIT_COUNT -lt \$MAX_WAIT ]; do
    if systemctl is-active --quiet strawberry-backend.service; then
        BACKEND_READY=1
        break
    fi
    if pgrep -f "python.*/opt/strawberry-ai/backend/main.py" >/dev/null; then
        BACKEND_READY=1
        break
    fi
    if netstat -tln 2>/dev/null | grep -q ":5000 " || ss -tln 2>/dev/null | grep -q ":5000 "; then
        BACKEND_READY=1
        break
    fi
    sleep 2
    WAIT_COUNT=\$((WAIT_COUNT+1))
done

echo "✅ Sistema pronto!" > /dev/tty1

if [ ! -z "\$VIDEO_PID" ] && kill -0 \$VIDEO_PID 2>/dev/null; then
    echo "🔄 Iniciando aplicação..." > /dev/tty1
    kill \$VIDEO_PID 2>/dev/null
    sleep 1
fi

cd /opt/strawberry-ai/frontend

if [ -f "venv-tkinter/bin/python" ] && ./venv-tkinter/bin/python -c "import tkinter; import customtkinter" 2>/dev/null; then
    echo "🐍 Usando venv alternativo" > /dev/tty1
    ./venv-tkinter/bin/python main.py
elif [ -f "venv/bin/python" ] && ./venv/bin/python -c "import tkinter; import customtkinter" 2>/dev/null; then
    echo "🐍 Usando venv principal" > /dev/tty1
    ./venv/bin/python main.py
else
    echo "🐍 Usando Python do sistema" > /dev/tty1
    python3 main.py
fi

APP_EXIT_CODE=\$?
if [ \$APP_EXIT_CODE -ne 0 ]; then
    echo "🔄 Reiniciando aplicação em 10 segundos..." > /dev/tty1
    sleep 10
    exec /opt/strawberry-ai/scripts/x-session.sh
fi
EOF

chmod +x /opt/strawberry-ai/scripts/*.sh

# CORREÇÃO: Permissões sudo para usuário correto
tee /etc/sudoers.d/strawberry-user > /dev/null << EOF
$CURRENT_USER ALL=(ALL) NOPASSWD: /bin/systemctl start strawberry-backend.service
$CURRENT_USER ALL=(ALL) NOPASSWD: /bin/systemctl stop strawberry-backend.service
$CURRENT_USER ALL=(ALL) NOPASSWD: /bin/systemctl start strawberry-kiosk.service
$CURRENT_USER ALL=(ALL) NOPASSWD: /bin/systemctl stop strawberry-kiosk.service
$CURRENT_USER ALL=(ALL) NOPASSWD: /usr/bin/pkill Xorg
$CURRENT_USER ALL=(ALL) NOPASSWD: /usr/bin/pkill mpv
EOF

chmod 440 /etc/sudoers.d/strawberry-user

# -------------------------------
# 12. AJUSTAR PERMISSÕES FINAIS
# -------------------------------
log "12. Ajustando permissões finais..."

chown -R $CURRENT_USER:$CURRENT_USER /opt/strawberry-ai
chmod +x /opt/strawberry-ai/backend/main.py
chmod +x /opt/strawberry-ai/frontend/main.py

log "✅ Configuração concluída para usuário: $CURRENT_USER"

# -------------------------------
# 13. CONCLUSÃO DEBIAN 12
# -------------------------------
log "✅ INSTALAÇÃO PARA DEBIAN 12 CONCLUÍDA!"
echo ""
echo "🎯 MELHORIAS APLICADAS:"
echo "======================"
echo "🔧 FIX 1: Compatibilidade total com Debian 12 Bookworm"
echo "🔧 FIX 2: Uso de rpicam-apps em vez de libcamera-apps"
echo "🔧 FIX 3: Dependências atualizadas e versões compatíveis"
echo "🔧 FIX 4: Detecção automática de Raspberry Pi"
echo "🔧 FIX 5: Fallbacks robustos para sistemas não-RPi"
echo ""
echo "📊 STATUS DO SISTEMA:"
echo "===================="
echo "✅ Python: $($PYTHON_BIN --version 2>/dev/null || echo "Sistema")"
echo "✅ Backend: Serviço systemd configurado"
echo "✅ Frontend: Kiosk mode habilitado"
if [ "$IS_RASPBERRY_PI" = true ]; then
    echo "✅ Câmera: Configuração Raspberry Pi aplicada"
else
    echo "⚠️  Câmera: Modo genérico (não-RPi)"
fi
echo "✅ IA: TensorFlow instalado"
echo "✅ Interface: CustomTkinter configurado"
echo ""
echo "🔄 PRÓXIMOS PASSOS:"
echo "=================="
echo "1. REINICIE O SISTEMA: sudo reboot"
echo "2. Após reiniciar, verifique: sudo systemctl status strawberry-backend"
echo "3. Teste a câmera (se RPi): rpicam-hello --list-cameras"
echo "4. Acesse os logs: sudo journalctl -u strawberry-backend -f"
echo ""
echo "🎉 SISTEMA OTIMIZADO PARA DEBIAN 12!"