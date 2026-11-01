
#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
LOG="${VPS_INIT_LOG_FILE:-$DIR/../install.log}"
PREFIX="[install > ${VPS_INIT_MODULE:-system}]"

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

configure_updates() {
    DEBIAN_FRONTEND=noninteractive apt-get install -y unattended-upgrades || return 1

    cat > /etc/apt/apt.conf.d/99-vps-initializer <<'EOF'
#clear Unattended-Upgrade::Allowed-Origins;
#clear Unattended-Upgrade::Origins-Pattern;

Unattended-Upgrade::Allowed-Origins {
    "${distro_id}:${distro_codename}-security";
};

APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
Unattended-Upgrade::Automatic-Reboot "false";
EOF

    systemctl enable --now apt-daily.timer apt-daily-upgrade.timer
}

verify() {
    [[ "$(timedatectl show -p Timezone --value)" == "Europe/Moscow" ]] &&
    [[ "$(timedatectl show -p NTP --value)" == "yes" ]] &&
    dpkg-query -W -f='${Status}' unattended-upgrades | grep -qx "install ok installed" &&
    systemctl is-enabled --quiet apt-daily-upgrade.timer
}

run "Обновление индекса APT" apt-get update

run "Обновление пакетов" \
    env DEBIAN_FRONTEND=noninteractive apt-get upgrade -y

run "Настройка обновлений безопасности" configure_updates

run "Установка часового пояса" \
    timedatectl set-timezone Europe/Moscow

run "Включение NTP" timedatectl set-ntp true

run "Проверка настроек" verify
