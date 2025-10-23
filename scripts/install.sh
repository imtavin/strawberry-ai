#!/bin/bash
# ===============================================================
# 🚀 Strawberry AI - Install Services Script (versão completa)
# Autor: Gustavo Espenchitt
# Descrição: Instala e configura o sistema Strawberry AI
# ===============================================================

APP_NAME="strawberry-ai"
APP_DIR="/opt/${APP_NAME}"
SCRIPTS_DIR="$(dirname "$(realpath "$0")")"
SYSTEMD_DIR="/etc/systemd/system"

BACKEND_DIR="${APP_DIR}/backend"
FRONTEND_DIR="${APP_DIR}/frontend"

PYTHON_BIN="/usr/bin/python3.10"

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
   error "Este script deve ser executado como root. Use: sudo ./install_services.sh"
fi

# -------------------------------
# Instalação do Python 3.10 (se necessário)
# -------------------------------
if [ ! -f "$PYTHON_BIN" ]; then
    warn "Python 3.10 não encontrado. Instalando dependências necessárias..."
    apt update -y
    apt install -y python3.10 python3.10-venv python3.10-distutils || error "Falha na instalação do Python 3.10"
else
    log "Python 3.10 encontrado em ${PYTHON_BIN}"
fi

# -------------------------------
# Instalação do pip (se necessário)
# -------------------------------
if ! command -v pip3 &> /dev/null; then
    log "Instalando pip3..."
    apt install -y python3-pip || error "Falha ao instalar pip3"
fi

# -------------------------------
# Copiar arquivos do projeto
# -------------------------------
log "Copiando arquivos do projeto para ${APP_DIR}..."
mkdir -p "${APP_DIR}"
cp -r "${SCRIPTS_DIR}/../backend" "${APP_DIR}/"
cp -r "${SCRIPTS_DIR}/../frontend" "${APP_DIR}/"

# -------------------------------
# Criar e configurar ambiente virtual do backend
# -------------------------------
log "Configurando ambiente virtual do backend..."
cd "${BACKEND_DIR}" || error "Falha ao acessar diretório do backend"
if [ ! -d "venv" ]; then
    ${PYTHON_BIN} -m venv venv || error "Falha ao criar venv do backend"
fi
source venv/bin/activate
pip install --upgrade pip
pip install -r requirements-backend.txt || error "Falha ao instalar dependências do backend"
deactivate

# -------------------------------
# Criar e configurar ambiente virtual do frontend
# -------------------------------
log "Configurando ambiente virtual do frontend..."
cd "${FRONTEND_DIR}" || error "Falha ao acessar diretório do frontend"
if [ ! -d "venv" ]; then
    ${PYTHON_BIN} -m venv venv || error "Falha ao criar venv do frontend"
fi
source venv/bin/activate
pip install --upgrade pip
pip install -r requirements-frontend.txt || error "Falha ao instalar dependências do frontend"
deactivate

# -------------------------------
# Instalar e habilitar serviços systemd
# -------------------------------
log "Instalando serviços systemd..."
cp "${SCRIPTS_DIR}/systemd/strawberry-backend.service" "${SYSTEMD_DIR}/" || error "Falha ao copiar serviço backend"
cp "${SCRIPTS_DIR}/systemd/strawberry-frontend.service" "${SYSTEMD_DIR}/" || error "Falha ao copiar serviço frontend"

# Recarregar systemd
systemctl daemon-reload

# Habilitar serviços no boot
systemctl enable strawberry-backend.service
systemctl enable strawberry-frontend.service

# -------------------------------
# Iniciar serviços
# -------------------------------
log "Iniciando serviços..."
systemctl restart strawberry-backend.service
systemctl restart strawberry-frontend.service

# -------------------------------
# Exibir status final
# -------------------------------
log "✅ Instalação concluída com sucesso!"
echo ""
echo "📦 Diretório da aplicação: ${APP_DIR}"
echo "🧩 Serviços instalados:"
echo "   - strawberry-backend.service"
echo "   - strawberry-frontend.service"
echo ""
echo "📊 Para verificar status:"
echo "   sudo systemctl status strawberry-backend"
echo "   sudo systemctl status strawberry-frontend"
echo ""
echo "📜 Logs em tempo real:"
echo "   sudo journalctl -u strawberry-backend -f"
echo "   sudo journalctl -u strawberry-frontend -f"
echo ""
