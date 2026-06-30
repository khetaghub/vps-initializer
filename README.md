# VPS Initializer

Этот проект выполняет базовую первичную настройку чистого Ubuntu-сервера через Ansible.

## Что делает сценарий

Запуск идет через два playbook-а:

1. `01-bootstrap-ssh.yml`
2. `02-check-admin-access.yml`

Они объединены в `ansible/site.yml` и выполняются одной командой.

## Что происходит на сервере

### Этап 1. Первичное подключение

Ansible подключается к серверу по параметрам из `ansible/inventory.ini`:

- под пользователем `initial_user`
- на порт `initial_ssh_port`
- по ключу или паролю, в зависимости от `initial_auth_method`

Если хост новый, режим `ssh_host_key_checking_mode=accept-new` автоматически добавляет SSH host key сервера в `known_hosts`.

### Этап 2. Базовая подготовка системы

На сервере:

- обновляется `apt` cache
- устанавливаются пакеты:
  - `sudo`
  - `openssh-server`
  - `fail2ban`

### Этап 3. Создание нового администратора

Создается пользователь `new_user`:

- с shell `/bin/bash`
- с домашней директорией
- в группе `sudo`

Публичный ключ из `new_user_public_key_path` добавляется этому пользователю в `authorized_keys`.

### Этап 4. Настройка sudo

Создается файл:

- `/etc/sudoers.d/{{ new_user }}`

Если `new_user_sudo_without_password=true`, пользователь получает `sudo` без запроса пароля.

Если `false`, создается обычное правило `sudo`.

Конфигурация валидируется через `visudo -cf`.

### Этап 5. Перенастройка SSH

Сценарий:

- меняет SSH-порт на `new_ssh_port`
- запрещает вход под `root`
- отключает парольную аутентификацию SSH
- отключает `KbdInteractiveAuthentication`
- отключает `ChallengeResponseAuthentication`
- оставляет вход только по публичному ключу
- запрещает пустые пароли
- отключает `X11Forwarding`
- отключает `AllowAgentForwarding`
- отключает `AllowTcpForwarding`
- уменьшает число попыток входа через `MaxAuthTries`
- ограничивает время на логин через `LoginGraceTime`
- настраивает `ClientAliveInterval` и `ClientAliveCountMax`
- разрешает вход только пользователю `new_user`

Дополнительный hardening пишется в:

- `/etc/ssh/sshd_config.d/99-hardening.conf`

Перед перезапуском SSH конфиг проверяется командой:

- `sshd -t`

После этого сервис `ssh` перезапускается, и Ansible ждет доступности нового порта.

### Этап 6. Настройка fail2ban

Создается jail для SSH:

- файл `/etc/fail2ban/jail.d/sshd.local`

Используются параметры из `inventory.ini`:

- `fail2ban_bantime`
- `fail2ban_findtime`
- `fail2ban_maxretry`

Также настраивается логирование fail2ban через:

- `/etc/fail2ban/fail2ban.local`

По умолчанию в текущем проекте:

- бан бессрочный, если `fail2ban_bantime=-1`
- лог пишется в `fail2ban_logtarget`
- уровень логирования задается через `fail2ban_loglevel`

После настройки сервис `fail2ban` включается и запускается.

### Этап 7. Проверка нового доступа

После изменения SSH-настроек запускается второй playbook, который:

- подключается уже под `new_user`
- использует новый SSH-порт `new_ssh_port`
- проверяет обычный вход через `whoami`
- проверяет работу `sudo`
- проверяет статус `fail2ban` для `sshd`
- выводит результаты в Ansible output

## Что в итоге меняется

После успешного запуска:

- вход по `root` через SSH отключен
- SSH слушает новый порт
- вход по паролю через SSH отключен
- вход разрешен только новому пользователю
- новый пользователь может администрировать сервер через `sudo`
- fail2ban защищает SSH и пишет собственный лог

## Запуск

### Запуск с Unix

```bash
make syntax-check install-collections run
```

### Запуск с Windows

```powershell
.\install-collections.ps1 && .\syntax-check.ps1 && .\run.ps1
```

### Чистый Ansible

```bash
ansible-playbook -i ansible/inventory.ini ansible/site.yml
```
