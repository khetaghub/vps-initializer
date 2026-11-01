
#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
LOG="${VPS_INIT_LOG_FILE:-$DIR/../install.log}"
PREFIX="[install > ${VPS_INIT_MODULE:-fail2ban}]"

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

# Проверка UFW
run "Проверка UFW" bash -c \
    "LC_ALL=C ufw status | grep -qx 'Status: active'"

# Установка Fail2ban
run "Установка Fail2ban" \
    env DEBIAN_FRONTEND=noninteractive apt-get install -y fail2ban python3-systemd

# Определение SSH-порта
log "Определение SSH-порта..."

port="$(/usr/sbin/sshd -T 2>>"$LOG" | awk '$1 == "port" {print $2}')"

if [[ ! "$port" =~ ^[0-9]+$ ]]; then
    log "Определение SSH-порта — ошибка"
    exit 1
fi

log "Определение SSH-порта — успешно ($port)"

# Настройка защиты
configure() {
    cat > /etc/fail2ban/jail.d/99-vps-initializer.local <<EOF
[sshd]
enabled = true
port = $port
backend = systemd
mode = aggressive
maxretry = 3
findtime = 86400
bantime = -1
banaction = ufw
EOF
}

# Ожидание готовности SSH jail
wait_sshd() {
    for ((i = 0; i < 60; i++)); do
        if fail2ban-client status sshd >/dev/null 2>&1; then
            return 0
        fi
        sleep 1
    done

    return 1
}

# Проверка параметров
check_setting() {
    local setting="$1"
    local expected="$2"
    local actual

    actual="$(fail2ban-client get sshd "$setting")" || return 1

    echo "$setting: ожидается $expected, получено $actual"
    [[ "$actual" == "$expected" ]]
}

check_action() {
    local actions

    actions="$(fail2ban-client get sshd actions)" || return 1

    echo "$actions"
    grep -qw ufw <<<"$actions"
}

# Установка и запуск
run "Настройка защиты SSH" configure
run "Проверка конфигурации" fail2ban-client -t
run "Включение Fail2ban" systemctl enable fail2ban
run "Запуск Fail2ban" systemctl restart fail2ban

# Проверка результатов
run "Проверка SSH-защиты" wait_sshd

run "Проверка службы Fail2ban" \
    systemctl is-active --quiet fail2ban

run "Проверка количества попыток" \
    check_setting maxretry 3

run "Проверка периода подсчёта" \
    check_setting findtime 86400

run "Проверка времени блокировки" \
    check_setting bantime -1

run "Проверка интеграции с UFW" \
    check_action
