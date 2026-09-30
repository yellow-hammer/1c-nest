# 1c-nest

Docker-образы для 1С:Предприятия, 1C:EDT и OneScript, собранные из кубиков. Каждый каталог репозитория - один кубик: он либо ставит что-то одно, либо добавляет слой поверх другого образа.

Рецепты открыты. Образы с платформой и EDT лежат приватными пакетами организации: лицензия 1С не разрешает их распространять. Такие же образы для себя собираются по рецептам, см. [Собрать у себя](#собрать-у-себя).

## Образы

`ghcr.io/yellow-hammer/1c-nest/<образ>:<тег>`

| Образ | Что внутри | Основа |
|---|---|---|
| `onescript:2.1.0`, `onescript:1.9.4` | OneScript и opm | Ubuntu 22.04 |
| `downloader:latest` | yard и `onec-download`: дистрибутивы с releases.1c.ru | `onescript:2.1.0` |
| `server:<версия>` | Сервер: агент кластера с ras, сервер хранилища, ibcmd, ibsrv, модули веб-сервера | Ubuntu 22.04 |
| `client:<версия>` | Конфигуратор, толстый и тонкий клиенты, ibcmd, ibsrv и сервер | Ubuntu 22.04 |
| `client-vnc:<версия>` | Окна клиента в браузере | `client` |
| `vrunner:<версия>` | OneScript 2.1, vanessa-runner 3 и Vanessa-ADD; `ENTRYPOINT vrunner` | `client` |
| `vrunner:<версия>-vrunner2` | OneScript 1.9 и vanessa-runner 2 | `client` |
| `vrunner:<версия>-vnc`, `vrunner:<версия>-vrunner2-vnc` | То же с окнами в браузере | `client-vnc` |
| `edt:<версия>` | 1C:EDT; `ENTRYPOINT 1cedtcli` | Ubuntu 22.04 |

`onescript` и `downloader` открытые, в остальных образах есть файлы 1С. Для них нужен вход с токеном GitHub, у которого есть право `read:packages`:

```bash
docker login ghcr.io -u <логин GitHub>
```

Версия в теге точная (`8.3.27.2342`) или линейка (`8.3.27`): тег линейки указывает на последнюю собранную сборку. Собираемые линейки перечислены в [versions.json](versions.json), новые сборки в них публикуются раз в неделю.

В клиенте отключена защита от опасных действий (`DisableUnsafeActionProtection`).

## Сервер

```bash
docker run -d --name 1c --hostname 1c \
  -p 1540-1541:1540-1541 -p 1545:1545 -p 1560-1591:1560-1591 \
  -v 1c-server:/home/usr1cv8/.1cv8 \
  ghcr.io/yellow-hammer/1c-nest/server:8.3.27
```

Кластер сообщает клиентам имя из `--hostname`: у них оно должно указывать на машину с Docker.

Команда контейнера по умолчанию `ragent`: агент кластера и сервер администрирования. Команда `crserver` поднимает сервер хранилища конфигураций, остальные (`ibsrv`, `ibcmd`, `rac`) выполняются как есть. Порты задают переменные:

| Переменная | По умолчанию |
|---|---|
| `RAGENT_PORT` | `1540` |
| `RAGENT_REGPORT` | `1541` |
| `RAGENT_RANGE` | `1560:1591` |
| `RAS_PORT` | `1545`, `none` - без сервера администрирования |
| `CRSERVER_PORT` | `1542` |

## Клиент

Конфигуратору и клиенту дисплей поднимает `1c-nest-display`, а команда идёт под владельцем рабочего каталога:

```bash
docker run --rm -v "$PWD:/workspace" ghcr.io/yellow-hammer/1c-nest/client:8.3.27 \
  1c-nest-display 1cv8 DESIGNER /F/workspace/ib /DumpConfigToFiles /workspace/src
```

В образах `-vnc` окна видны в браузере на http://localhost:6080 при `-p 127.0.0.1:6080:6080`, в клиенте VNC - на порту 5900.

## В 1C: Platform Tools

```json
{
  "1c-platform-tools.docker.enabled": true,
  "1c-platform-tools.docker.image": "ghcr.io/yellow-hammer/1c-nest/vrunner:8.3.27"
}
```

Проекту с настройками vanessa-runner 2 (`env.json`) нужен образ с тегом `-vrunner2`.

Команды vrunner идут под владельцем каталога проекта, поэтому созданные ими файлы принадлежат ему.

Конфигуратору и клиенту в контейнере дисплей поднимается сам, поэтому пакетные команды и тесты работают в любом образе. Чтобы видеть окна, есть три способа, настройка для каждого задаётся в `1c-platform-tools.docker.runArgs`:

| Где | Образ | `docker.runArgs` |
|---|---|---|
| Любая система, окна в браузере на http://localhost:6080 | `-vnc` | `["-p", "127.0.0.1:6080:6080", "-p", "127.0.0.1:5900:5900"]` |
| Windows 11 с Docker Desktop, окна на рабочем столе | любой | `["-v", "/run/desktop/mnt/host/wslg/.X11-unix:/tmp/.X11-unix", "-e", "DISPLAY=:0"]` |
| Linux с X-сервером, после `xhost +si:localuser:$USER` | любой | `["-e", "DISPLAY", "-v", "/tmp/.X11-unix:/tmp/.X11-unix"]` |

Порты из `docker.runArgs` расширение публикует только Предприятию и Конфигуратору, открытым в контейнере, поэтому остальные команды работают и при открытом клиенте. Окна тестов в браузере не видны, а второй клиент не запустится, пока открыт первый: порт занят.

Переменные окружения обёртки дисплея:

| Переменная | Значение |
|---|---|
| `VNC_PASSWORD` | Пароль VNC, по умолчанию без пароля |
| `ONEC_NEST_SCREEN` | Размер экрана, по умолчанию `1920x1080x24` |
| `ONEC_NEST_DISPLAY=none` | Запуск без дисплея |
| `ONEC_NEST_AS_OWNER=0` | Команда идёт от текущего пользователя, а не от владельца рабочего каталога: для задач `container:` в CI, где шаги идут от root |

## OneScript и загрузчик

```bash
docker run --rm -v "$PWD:/workspace" -w /workspace ghcr.io/yellow-hammer/1c-nest/onescript:2.1.0 oscript main.os
docker run --rm -e ONEC_LOGIN -e ONEC_PASSWORD -v "$PWD/distr:/distr" \
  ghcr.io/yellow-hammer/1c-nest/downloader platform 8.3.27.2342 /distr
```

`ONEC_LOGIN` и `ONEC_PASSWORD` - учётная запись releases.1c.ru. Загрузчик также находит последнюю сборку линейки: `latest platform 8.3.27`, `latest edt 2026.1`.

## Лицензия

Командам через ibcmd и ibsrv лицензия не нужна, конфигуратору, клиентам и сеансам на сервере нужна.

- Программную лицензию платформа ищет в `/var/1C/licenses`. Она привязана к имени и MAC-адресу машины, у контейнера они каждый раз новые, поэтому задайте `--hostname` и `--mac-address`.
- Сетевой ключ HASP описывается в `/opt/1cv8/conf/nethasp.ini`.

## Собрать у себя

Нужен Docker с BuildKit. Дистрибутив скачивается при сборке, учётная запись releases.1c.ru передаётся секретами из переменных окружения и в образ не попадает:

```bash
export ONEC_LOGIN=<логин> ONEC_PASSWORD=<пароль>
docker build --secret id=ONEC_LOGIN --secret id=ONEC_PASSWORD \
  --build-arg ONEC_VERSION=8.3.27.2342 -t client:8.3.27.2342 client
```

Скачивает дистрибутив образ `downloader` отсюда, свой задаётся `--build-arg DOWNLOADER_IMAGE=<образ>`. Скачанный раньше дистрибутив подставляется вместо скачивания, секреты тогда не нужны: `--build-context distr=<каталог>`. Для платформы в каталоге лежит `setup-full-<версия>-x86_64.run`, для EDT - распакованный офлайн-дистрибутив.

Слои собираются поверх готовых образов, своих или отсюда. Например, `vrunner:<версия>-vnc` - это client, vnc, onescript и vrunner:

```bash
docker build --build-arg BASE_IMAGE=client:8.3.27.2342 -t client-vnc:8.3.27.2342 vnc
docker build --build-arg BASE_IMAGE=client-vnc:8.3.27.2342 -t client-vnc-onescript:8.3.27.2342 onescript
docker build --build-arg BASE_IMAGE=client-vnc-onescript:8.3.27.2342 -t vrunner:8.3.27.2342-vnc vrunner
```

Для vanessa-runner 2 слой onescript собирается с `--build-arg ONESCRIPT_VERSION=1.9.4`, а vrunner - с `--build-arg VRUNNER_VERSION=2.6.1`.

Все образы версии собирает [scripts/build.sh](scripts/build.sh): `scripts/build.sh platform 8.3.27.2342`, `scripts/build.sh edt 2026.1.3`.

В форке этого репозитория образы собирает workflow «Образы»: добавьте секреты Actions `ONEC_LOGIN` и `ONEC_PASSWORD` и запустите его из main. Образы появятся в `ghcr.io/<владелец форка>/1c-nest` приватными. Форк публичного репозитория тоже публичный, а workflow из чужого запроса на слияние может скачать приватные образы. Перед первой публикацией включите в настройках Actions одобрение запусков для всех внешних участников.

Образы с платформой и EDT не публикуйте открыто.
