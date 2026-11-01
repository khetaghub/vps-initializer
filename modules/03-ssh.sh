
#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
LOG="${VPS_INIT_LOG_FILE:-$DIR/../install.log}"
PREFIX="[install > ${VPS_INIT_MODULE:-ssh}]"
MAIN="/etc/ssh/sshd_config"
BACKUP="/etc/ssh/sshd_config.vps-initializer.bak"
SSHD="/usr/sbin/sshd"

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

if [[ ! -x "$SSHD" ]] ||
   ! systemctl is-active --quiet ssh.socket; then
    log "Не найден SSH или неактивен ssh.socket — ошибка"
    exit 1
fi

mkdir -p /run/sshd
run "Проверка SSH" "$SSHD" -t

settings="$("$SSHD" -T 2>>"$LOG")"
mapfile -t current_ports < <(
    printf '%s\n' "$settings" |
    awk '$1 == "port" {print $2}'
)

if (( ${#current_ports[@]} != 1 )); then
    log "Ожидался один действующий SSH-порт — ошибка"
    exit 1
fi

old_port="${current_ports[0]}"

log "Введите новый SSH-порт [$old_port]:"
read -r port </dev/tty
port="${port:-$old_port}"

if [[ ! "$port" =~ ^[0-9]{1,5}$ ]] ||
   (( 10#$port < 1 || 10#$port > 65535 )); then
    log "Некорректный порт — ошибка"
    exit 1
fi

port="$((10#$port))"

if [[ "$port" != "$old_port" ]] &&
   ss -H -ltn "sport = :$port" | grep -q .; then
    log "Порт $port уже занят — ошибка"
    exit 1
fi

run "Резервное копирование SSH" \
    cp -a "$MAIN" "$BACKUP"

# Подготовка конфигурации
write_config() {
    local stage="$1" tmp
    tmp="$(mktemp "${MAIN}.tmp.XXXXXX")" || return 1

    {
        echo "Port $port"

        if [[ "$stage" == "test" &&
              "$port" != "$old_port" ]]; then
            echo "Port $old_port"
        fi

        if [[ "$stage" == "final" ]]; then
            cat <<'EOF'
PermitRootLogin no
PasswordAuthentication no
KbdInteractiveAuthentication no
PubkeyAuthentication yes
PermitEmptyPasswords no
MaxAuthTries 3
LoginGraceTime 30
EOF
        fi

        awk '
            /^[[:space:]]*Port[[:space:]]+/ {
                print "# " $0
                next
            }
            { print }
        ' "$BACKUP"
    } >"$tmp" || {
        rm -f "$tmp"
        return 1
    }

    chmod --reference="$BACKUP" "$tmp"
    mv -f "$tmp" "$MAIN"
}

# Восстановление при ошибке
restore=1

rollback() {
    local code=$?
    trap - EXIT INT TERM HUP

    if (( restore )); then
        log "Восстановление SSH..."

        if cp -a "$BACKUP" "$MAIN" >>"$LOG" 2>&1 &&
           systemctl daemon-reload >>"$LOG" 2>&1 &&
           systemctl restart ssh.socket >>"$LOG" 2>&1; then

            if systemctl is-active --quiet ssh.service; then
                systemctl reload ssh.service >>"$LOG" 2>&1 || true
            fi

            log "Восстановление SSH — выполнено"
        else
            log "Восстановление SSH — ошибка"
        fi
    fi

    exit "$code"
}

trap rollback EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP

# Временно сохраняем старый порт
run "Настройка SSH-портов" write_config test
run "Проверка конфигурации" "$SSHD" -t

settings="$("$SSHD" -T 2>>"$LOG")"

if ! grep -qx "port $port" <<<"$settings"; then
    log "Новый порт отсутствует в конфигурации — ошибка"
    exit 1
fi

run "Обновление systemd" systemctl daemon-reload
run "Применение SSH-портов" systemctl restart ssh.socket

if systemctl is-active --quiet ssh.service; then
    run "Обновление SSH-службы" systemctl reload ssh.service
fi

if ! ss -H -ltn "sport = :$port" | grep -q . ||
   {
       [[ "$port" != "$old_port" ]] &&
       ! ss -H -ltn "sport = :$old_port" | grep -q .
   }; then
    log "Проверка SSH-портов — ошибка"
    exit 1
fi

# Ручная проверка подключения
log "Проверьте вход из второго терминала:"
log "ssh -o PreferredAuthentications=publickey -o PasswordAuthentication=no -o KbdInteractiveAuthentication=no -p $port ИМЯ_АДМИНА@IP_VPS"
log "После входа выполните sudo -v"
log "Введите YES после проверки (5 минут):"

if ! read -r -t 300 answer </dev/tty ||
   [[ "$answer" != "YES" ]]; then
    log "Подключение не подтверждено — отмена"
    exit 1
fi

# Окончательная настройка безопасности
run "Настройка безопасности SSH" write_config final
run "Проверка конфигурации" "$SSHD" -t

settings="$("$SSHD" -T 2>>"$LOG")"

for required in \
    "port $port" \
    "permitrootlogin no" \
    "passwordauthentication no" \
    "kbdinteractiveauthentication no" \
    "pubkeyauthentication yes" \
    "permitemptypasswords no" \
    "maxauthtries 3" \
    "logingracetime 30"; do

    if ! grep -qx "$required" <<<"$settings"; then
        log "Настройка $required не применена — ошибка"
        exit 1
    fi
done

if [[ "$port" != "$old_port" ]] &&
   grep -qx "port $old_port" <<<"$settings"; then
    log "Старый порт остался в конфигурации — ошибка"
    exit 1
fi

run "Обновление systemd" systemctl daemon-reload
run "Применение защиты SSH" systemctl restart ssh.socket

if systemctl is-active --quiet ssh.service; then
    run "Обновление SSH-службы" systemctl reload ssh.service
fi

if ! ss -H -ltn "sport = :$port" | grep -q . ||
   {
       [[ "$port" != "$old_port" ]] &&
       ss -H -ltn "sport = :$old_port" | grep -q .
   }; then
    log "Проверка SSH-портов — ошибка"
    exit 1
fi

restore=0
trap - EXIT INT TERM HUP

log "Настройка SSH — успешно"
