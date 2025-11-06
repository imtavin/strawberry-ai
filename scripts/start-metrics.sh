#!/bin/bash
# Iniciar coletor de métricas diretamente

# Parar qualquer coletor existente
pkill -f "metrics-collector.sh" 2>/dev/null

# Iniciar novo coletor
nohup /opt/strawberry-ai/scripts/metrics-collector.sh > /opt/strawberry-ai/logs/metrics-collector.log 2>&1 &

echo "Coletor iniciado com PID: $!"
echo "Verifique os logs: tail -f /opt/strawberry-ai/logs/metrics-collector.log"
echo "Ver métricas: tail -f /opt/strawberry-ai/logs/metrics.log"
