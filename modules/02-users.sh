
#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
LOG="${VPS_INIT_LOG_FILE:-$DIR/../install.log}"
PREFIX="[install > ${VPS_INIT_MODULE:-users}]"

umask 077
touch "$LOG"

log() {
    echo "$PREFIX $1" | tee -a "$LOG"
}

run() {
    local task="$1"
    shift

    log "$task..."
    if "$@" >> "$LOG" 2>&1; then
        log "$task — успешно"
    else
        log "$task — ошибка"
        return 1
    fi
}

if [[ $EUID -ne 0 ]]; then
    log "Требуются права root — ошибка"
    exit 1
fi

# 1. Запрос имени
log "Введите имя нового администратора:"
read -r username </dev/tty

if [[ ! "$username" =~ ^[a-z_][a-z0-9_-]*$ || "$username" == "root" ]]; then
    log "Недопустимое имя пользователя — ошибка"
    exit 1
fi

# 2. Проверка существования
if id "$username" >/dev/null 2>&1; then
    log "Пользователь '$username' уже существует — ошибка"
    exit 1
fi

# 3. Создание администратора
run "Создание администратора" useradd -m -s /bin/bash "$username"
run "Настройка sudo" usermod -aG sudo "$username"

# 4. Установка пароля
log "Установка пароля для '$username'..."

if passwd "$username" </dev/tty >/dev/tty 2>&1; then
    log "Установка пароля — успешно"
else
    log "Установка пароля — ошибка"
    exit 1
fi

# 5. Настройка SSH-ключа
log "Введите публичный SSH-ключ для '$username':"
read -r ssh_key </dev/tty

if [[ ! "$ssh_key" =~ ^(ssh-|ecdsa-) || "$ssh_key" != *' '* ]]; then
    log "Некорректный формат SSH-ключа — ошибка"
    exit 1
fi

home="$(getent passwd "$username" | cut -d: -f6)"
ssh_dir="$home/.ssh"
key_file="$ssh_dir/authorized_keys"

configure_ssh_key() {
    local group
    group="$(id -gn "$username")"

    install -d -m 700 -o "$username" -g "$group" "$ssh_dir"
    touch "$key_file"

    if ! grep -Fxq -- "$ssh_key" "$key_file"; then
        printf '%s\n' "$ssh_key" >> "$key_file"
    fi

    chown "$username:$group" "$key_file"
    chmod 600 "$key_file"
}

# 6. Проверка результатов
verify() {
    id -nG "$username" | tr ' ' '\n' | grep -Fxq sudo &&
    [[ "$(stat -c '%U:%a' "$ssh_dir")" == "$username:700" ]] &&
    [[ "$(stat -c '%U:%a' "$key_file")" == "$username:600" ]] &&
    grep -Fxq -- "$ssh_key" "$key_file"
}

run "Настройка SSH-ключа" configure_ssh_key
run "Проверка пользователя" verify

