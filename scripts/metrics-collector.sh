#!/bin/bash
# Coletor de métricas completo para estudo de desempenho

METRICS_LOG="/opt/strawberry-ai/logs/metrics.log"
INTERVAL=5

# Criar diretórios
mkdir -p /opt/strawberry-ai/logs

echo "Iniciando coletor de métricas completo (PID: $$)" > /opt/strawberry-ai/logs/metrics-collector.log

# Cabeçalho do CSV com todas as métricas
echo "timestamp,temp_cpu,cpu_usage,mem_usage,mem_total_mb,mem_used_mb,mem_free_mb,disk_usage,disk_used_mb,disk_free_mb,process_count,thread_count,load_1min,load_5min,load_15min,network_rx_mb,network_tx_mb,swap_used_mb,swap_total_mb,uptime_seconds,io_read_kb,io_write_kb,active_processes,running_processes,blocked_processes" > "$METRICS_LOG"

# Variáveis para cálculo de rede
prev_rx_bytes=0
prev_tx_bytes=0
prev_io_read=0
prev_io_write=0

# Função para obter interface de rede ativa
get_network_interface() {
    if [ -f /sys/class/net/eth0/operstate ] && grep -q "up" /sys/class/net/eth0/operstate 2>/dev/null; then
        echo "eth0"
    elif [ -f /sys/class/net/wlan0/operstate ] && grep -q "up" /sys/class/net/wlan0/operstate 2>/dev/null; then
        echo "wlan0"
    else
        # Tenta encontrar qualquer interface up
        ip -o link show | awk -F': ' '$3 == "UP" {print $2; exit}'
    fi
}

# Função para obter estatísticas de IO
get_io_stats() {
    # Lê do /proc/diskstats para o dispositivo principal (normalmente mmcblk0)
    if [ -f /proc/diskstats ]; then
        # Tenta obter estatísticas do dispositivo de root
        root_device=$(df / | awk 'NR==2 {print $1}' | sed 's/.*\///')
        if [ -n "$root_device" ]; then
            io_data=$(grep "$root_device" /proc/diskstats | head -1)
            if [ -n "$io_data" ]; then
                # Campos: reads completed, sectors read, writes completed, sectors written
                read_sectors=$(echo $io_data | awk '{print $6}')
                write_sectors=$(echo $io_data | awk '{print $10}')
                echo "$((read_sectors * 512 / 1024)):$((write_sectors * 512 / 1024))"
                return
            fi
        fi
    fi
    echo "0:0"
}

NETWORK_INTERFACE=$(get_network_interface)

while true; do
    # Timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    # ===== TEMPERATURA =====
    if [ -f /sys/class/thermal/thermal_zone0/temp ]; then
        temp_raw=$(cat /sys/class/thermal/thermal_zone0/temp)
        temp_cpu=$(echo "scale=1; $temp_raw/1000" | bc -l 2>/dev/null || echo "0")
    else
        temp_cpu="0"
    fi
    
    # ===== CPU =====
    cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print 100 - $8}' | cut -d'.' -f1)
    
    # Load Average
    load=$(cat /proc/loadavg)
    load_1min=$(echo $load | awk '{print $1}')
    load_5min=$(echo $load | awk '{print $2}')
    load_15min=$(echo $load | awk '{print $3}')
    
    # ===== MEMÓRIA =====
    mem_info=$(free -m | grep Mem)
    mem_total=$(echo $mem_info | awk '{print $2}')
    mem_used=$(echo $mem_info | awk '{print $3}')
    mem_free=$(echo $mem_info | awk '{print $4}')
    mem_usage=$(echo "scale=1; $mem_used * 100 / $mem_total" | bc -l 2>/dev/null || echo "0")
    
    # Swap
    swap_info=$(free -m | grep Swap)
    swap_total=$(echo $swap_info | awk '{print $2}')
    swap_used=$(echo $swap_info | awk '{print $3}')
    
    # ===== DISCO =====
    disk_info=$(df / | awk 'NR==2')
    disk_usage=$(echo $disk_info | awk '{print $5}' | sed 's/%//')
    disk_used_mb=$(echo "scale=0; $(echo $disk_info | awk '{print $3}') / 1024" | bc -l 2>/dev/null || echo "0")
    disk_free_mb=$(echo "scale=0; $(echo $disk_info | awk '{print $4}') / 1024" | bc -l 2>/dev/null || echo "0")
    
    # ===== PROCESSOS =====
    process_count=$(ps -e --no-headers | wc -l)
    thread_count=$(ps -eL --no-headers 2>/dev/null | wc -l || echo "0")
    
    # Estatísticas de processos
    running_processes=$(ps -e -o state --no-headers | grep -c '^R' || echo "0")
    sleeping_processes=$(ps -e -o state --no-headers | grep -c '^S' || echo "0")
    blocked_processes=$(ps -e -o state --no-headers | grep -c '^D' || echo "0")
    active_processes=$((running_processes + sleeping_processes))
    
    # ===== REDE =====
    if [ -n "$NETWORK_INTERFACE" ] && [ -f "/sys/class/net/$NETWORK_INTERFACE/statistics/rx_bytes" ]; then
        current_rx_bytes=$(cat /sys/class/net/$NETWORK_INTERFACE/statistics/rx_bytes)
        current_tx_bytes=$(cat /sys/class/net/$NETWORK_INTERFACE/statistics/tx_bytes)
        
        # Calcular diferença desde a última leitura
        if [ $prev_rx_bytes -gt 0 ]; then
            rx_diff=$((current_rx_bytes - prev_rx_bytes))
            tx_diff=$((current_tx_bytes - prev_tx_bytes))
            network_rx_mb=$(echo "scale=2; $rx_diff / 1024 / 1024" | bc -l 2>/dev/null || echo "0")
            network_tx_mb=$(echo "scale=2; $tx_diff / 1024 / 1024" | bc -l 2>/dev/null || echo "0")
        else
            network_rx_mb="0"
            network_tx_mb="0"
        fi
        
        prev_rx_bytes=$current_rx_bytes
        prev_tx_bytes=$current_tx_bytes
    else
        network_rx_mb="0"
        network_tx_mb="0"
    fi
    
    # ===== I/O DISCO =====
    io_stats=$(get_io_stats)
    current_io_read=$(echo $io_stats | cut -d: -f1)
    current_io_write=$(echo $io_stats | cut -d: -f2)
    
    # Calcular diferença
    if [ $prev_io_read -gt 0 ]; then
        io_read_diff=$((current_io_read - prev_io_read))
        io_write_diff=$((current_io_write - prev_io_write))
    else
        io_read_diff="0"
        io_write_diff="0"
    fi
    
    prev_io_read=$current_io_read
    prev_io_write=$current_io_write
    
    # ===== UPTIME =====
    uptime_seconds=$(awk '{print int($1)}' /proc/uptime)
    
    # ===== SALVAR NO LOG =====
    echo "$timestamp,$temp_cpu,$cpu_usage,$mem_usage,$mem_total,$mem_used,$mem_free,$disk_usage,$disk_used_mb,$disk_free_mb,$process_count,$thread_count,$load_1min,$load_5min,$load_15min,$network_rx_mb,$network_tx_mb,$swap_used,$swap_total,$uptime_seconds,$io_read_diff,$io_write_diff,$active_processes,$running_processes,$blocked_processes" >> "$METRICS_LOG"
    
    # Debug no log do coletor
    echo "$timestamp - CPU: $cpu_usage% Mem: $mem_usage% Temp: $temp_cpu°C Load: $load_1min" >> /opt/strawberry-ai/logs/metrics-collector.log
    
    sleep $INTERVAL
done
