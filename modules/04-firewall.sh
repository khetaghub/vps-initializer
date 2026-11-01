
#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
LOG="${VPS_INIT_LOG_FILE:-$DIR/../install.log}"
PREFIX="[install > ${VPS_INIT_MODULE:-firewall}]"

umask 077
touch "$LOG"

log() {
    echo "$PREFIX $1" | tee -a "$LOG"
}

run() {
    local task="$1"
    shift

    log "$task..."

    if "$@" >>"$LOG" 2>&1; then
        log "$task — успешно"
    else
        log "$task — ошибка"
        return 1
    fi
}

if (( EUID != 0 )); then
    log "Требуются права root — ошибка"
    exit 1
fi

# Установка UFW
run "Установка UFW" \
    env DEBIAN_FRONTEND=noninteractive apt-get install -y ufw

# Определение SSH-порта
log "Определение SSH-порта..."

if ! ports="$(/usr/sbin/sshd -T 2>>"$LOG" | awk '$1 == "port" {print $2}')" ||
   [[ ! "$ports" =~ ^[0-9]+$ ]] ||
   ! ss -H -ltn "sport = :$ports" | grep -q .; then
    log "Определение SSH-порта — ошибка"
    exit 1
fi

port="$ports"
log "Определение SSH-порта — успешно ($port)"

# Проверка существующих правил
if ! existing="$(ufw show added 2>>"$LOG")"; then
    log "Проверка правил UFW — ошибка"
    exit 1
fi

if printf '%s\n' "$existing" |
   grep '^ufw ' |
   grep -Fvx "ufw allow $port/tcp" |
   grep -q .; then
    printf '%s\n' "$existing" >>"$LOG"
    log "Найдены другие правила UFW — ошибка (см. install.log)"
    exit 1
fi

# Поддержка IPv4 и IPv6
configure_ipv6() {
    if grep -q '^IPV6=' /etc/default/ufw; then
        sed -i 's/^IPV6=.*/IPV6=yes/' /etc/default/ufw
    else
        echo 'IPV6=yes' >>/etc/default/ufw
    fi
}

# Проверка итоговой конфигурации
verify() {
    local status
    status="$(LC_ALL=C ufw status verbose)" || return 1

    grep -qx 'Status: active' <<<"$status" &&
    grep -q '^Default: deny (incoming), allow (outgoing)' <<<"$status" &&
    grep -Eq "^${port}/tcp[[:space:]]+ALLOW IN" <<<"$status" &&
    grep -Eq "^${port}/tcp \(v6\)[[:space:]]+ALLOW IN" <<<"$status"
}

run "Настройка IPv6" configure_ipv6

run "Запрет входящих подключений" \
    ufw default deny incoming

run "Разрешение исходящих подключений" \
    ufw default allow outgoing

run "Разрешение SSH-порта $port" \
    ufw allow "$port/tcp"

run "Включение Firewall" \
    ufw --force enable

run "Проверка Firewall" verify
