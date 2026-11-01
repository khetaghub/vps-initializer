
#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
LOG="${VPS_INIT_LOG_FILE:-$DIR/../install.log}"
PREFIX="[install > ${VPS_INIT_MODULE:-users}]"
USERNAME="amnezia-vpn"

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

# 1. Проверка существования пользователя
if id "$USERNAME" >/dev/null 2>&1; then
    log "Пользователь '$USERNAME' уже существует — ошибка"
    exit 1
fi

# 2. Запрос SSH-ключа
log "Введите публичный SSH-ключ для '$USERNAME':"
read -r ssh_key </dev/tty

if [[ ! "$ssh_key" =~ ^(ssh-|ecdsa-|sk-) ]]; then
    log "Некорректный формат SSH-ключа — ошибка"
    exit 1
fi

# Проверка корректности публичного ключа
key_tmp="$(mktemp)"
printf '%s\n' "$ssh_key" > "$key_tmp"

if ! ssh-keygen -lf "$key_tmp" >/dev/null 2>&1; then
    rm -f "$key_tmp"
    log "Некорректный публичный SSH-ключ — ошибка"
    exit 1
fi

rm -f "$key_tmp"

# 3. Генерация пароля: 24 символа, 96 бит энтропии
password="$(od -An -N12 -tx1 /dev/urandom | tr -d '[:space:]')"

set_password() {
    printf '%s:%s\n' "$USERNAME" "$password" | chpasswd
}

# 4. Настройка sudo без пароля
configure_sudo() {
    local target="/etc/sudoers.d/90-vps-initializer-$USERNAME"
    local tmp

    tmp="$(mktemp)" || return 1

    if ! printf '%s ALL=(ALL:ALL) NOPASSWD:ALL\n' "$USERNAME" > "$tmp" ||
       ! chmod 440 "$tmp" ||
       ! visudo -cf "$tmp" >/dev/null; then
        rm -f "$tmp"
        return 1
    fi

    if ! install -o root -g root -m 440 "$tmp" "$target"; then
        rm -f "$tmp"
        return 1
    fi

    rm -f "$tmp"

    if ! visudo -cf /etc/sudoers >/dev/null; then
        rm -f "$target"
        return 1
    fi
}

# 5. Создание и настройка пользователя
run "Создание пользователя '$USERNAME'" useradd -m -s /bin/bash "$USERNAME"
run "Добавление в группу sudo" usermod -aG sudo "$USERNAME"
run "Установка сгенерированного пароля" set_password
run "Настройка sudo без пароля" configure_sudo

# 6. Настройка SSH
home="$(getent passwd "$USERNAME" | cut -d: -f6)"
ssh_dir="$home/.ssh"
key_file="$ssh_dir/authorized_keys"

configure_ssh_key() {
    local group
    group="$(id -gn "$USERNAME")" || return 1

    install -d -m 700 -o "$USERNAME" -g "$group" "$ssh_dir" || return 1
    touch "$key_file" || return 1

    if ! grep -Fxq -- "$ssh_key" "$key_file"; then
        printf '%s\n' "$ssh_key" >> "$key_file" || return 1
    fi

    chown "$USERNAME:$group" "$key_file" || return 1
    chmod 600 "$key_file"
}

# 7. Проверка
verify() {
    id -nG "$USERNAME" | tr ' ' '\n' | grep -Fxq sudo &&
    runuser -u "$USERNAME" -- sudo -n true &&
    [[ "$(stat -c '%U:%a' "$ssh_dir")" == "$USERNAME:700" ]] &&
    [[ "$(stat -c '%U:%a' "$key_file")" == "$USERNAME:600" ]] &&
    grep -Fxq -- "$ssh_key" "$key_file"
}

run "Настройка SSH-ключа" configure_ssh_key
run "Проверка пользователя" verify

# 8. Показ учётных данных только в терминале
printf '\n%s\n' "[install > users] Пользователь: $USERNAME"
printf '%s\n' "[install > users] Пароль: $password"
printf '%s\n\n' "[install > users] Сохраните пароль: повторно он не выводится."
