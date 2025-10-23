#!/bin/bash

# Cria diretório de capturas
sudo mkdir -p /capture
sudo chown $USER:$USER /capture
sudo chmod 755 /capture

# Adiciona permissão de escrita para o serviço
sudo usermod -aG video $USER

echo "✅ Diretório /capture configurado com sucesso"
echo "📸 As fotos serão salvas como: classificação-confiança-data_hora.jpg"