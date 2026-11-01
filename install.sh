
#!/usr/bin/env bash
set -euo pipefail

if (( EUID != 0 )); then
    echo "[install] Требуются права root"
    exit 1
fi

SOURCE="${BASH_SOURCE[0]:-}"
DIR=""

if [[ -n "$SOURCE" && -f "$SOURCE" ]]; then
    DIR="$(cd "$(dirname "$SOURCE")" && pwd)"
fi

# При запуске через curl скачиваем проект целиком
if [[ -z "$DIR" || ! -d "$DIR/modules" ]]; then
    DEST="/opt/vps-initializer"
    ARCHIVE="$(mktemp)"
    trap 'rm -f "$ARCHIVE"' EXIT

    if [[ -e "$DEST" ]]; then
        echo "[install] Каталог $DEST уже существует — ошибка"
        exit 1
    fi

    echo "[install] Скачивание проекта..."
    curl -fsSL \
        "https://github.com/khetaghub/vps-initializer/archive/refs/heads/amnezia-vpn.tar.gz" \
        -o "$ARCHIVE"

    mkdir -p "$DEST"
    if ! tar -xzf "$ARCHIVE" -C "$DEST" --strip-components=1; then
        echo "[install] Распаковка проекта — ошибка"
        exit 1
    fi

    if [[ ! -f "$DEST/install.sh" || ! -d "$DEST/modules" ]]; then
        echo "[install] Установочные скрипты не найдены — ошибка"
        exit 1
    fi

    rm -f "$ARCHIVE"
    trap - EXIT

    exec bash "$DEST/install.sh"
fi

# Локальный запуск модулей
LOG="$DIR/install.log"
umask 077
touch "$LOG"
chmod 600 "$LOG"

log() {
    echo "[install] $1" | tee -a "$LOG"
}

echo "=== $(date) ===" >> "$LOG"

modules=("$DIR"/modules/[0-9][0-9]-*.sh)

if [[ ! -f "${modules[0]}" ]]; then
    log "Модули не найдены"
    exit 1
fi

for module in "${modules[@]}"; do
    name="$(basename "$module" .sh)"
    name="${name#??-}"

    echo "[install > $name] Запуск..." | tee -a "$LOG"

    if VPS_INIT_LOG_FILE="$LOG" VPS_INIT_MODULE="$name" \
        bash "$module" 2>>"$LOG"; then

        echo "[install > $name] Успешно" | tee -a "$LOG"
    else
        echo "[install > $name] Ошибка" | tee -a "$LOG"
        exit 1
    fi
done

log "Установка завершена успешно"
