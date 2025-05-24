# Конфигурация Terraform для создания отказоустойчивой инфраструктуры в Yandex Cloud
# Этот файл создает:
# - 2 виртуальные машины с веб-серверами
# - Сетевую инфраструктуру (VPC, подсеть)
# - Балансировщик нагрузки для распределения трафика

# Блок terraform определяет требования к провайдерам
terraform {
  required_providers {
    yandex = {
      source  = "yandex-cloud/yandex"  # Официальный провайдер Yandex Cloud
      version = "~> 0.80.0"            # Версия провайдера
    }
  }
}

# Настройка провайдера Yandex Cloud
# Здесь указываются параметры подключения к облаку
provider "yandex" {
  service_account_key_file = "e:/Проект/Домашнее задание к занятию «Отказоустойчивость в облаке»/authorized_key.json"  # Путь к файлу с ключом сервисного аккаунта
  cloud_id                 = "XXXXXXXXXXXXXXXXXXX"     # Идентификатор облака
  folder_id                = "XXXXXXXXXXXXXXXXXXX"     # Идентификатор папки в облаке
  zone                     = "ru-central1-a"            # Зона доступности по умолчанию
}

# Создание виртуальных машин для веб-серверов
# Создаем 2 идентичные ВМ для обеспечения отказоустойчивости
resource "yandex_compute_instance" "vm" {
  count       = 2                           # Количество создаваемых ВМ
  name        = "vm-${count.index + 1}"     # Имя ВМ (vm-1, vm-2)
  platform_id = "standard-v3"               # Платформа Intel Ice Lake

  # Конфигурация ресурсов ВМ
  resources {
    cores         = 2   # Количество vCPU
    memory        = 2   # Объем RAM в ГБ
    core_fraction = 20  # Гарантированная доля vCPU (20% для экономии)
  }

  # Настройка загрузочного диска
  boot_disk {
    initialize_params {
      image_id = "fd8huqdhr65m771g1bka"  # ID образа Ubuntu 20.04 LTS
      size     = 15                     # Размер диска в ГБ
      type     = "network-hdd"          # Тип диска (HDD для экономии)
    }
  }

  # Настройка сетевого интерфейса
  network_interface {
    subnet_id = yandex_vpc_subnet.subnet-1.id  # Подключение к созданной подсети
    nat       = true                           # Включение NAT для доступа в интернет
  }

  # Политика планирования (прерываемые ВМ для экономии)
  scheduling_policy {
    preemptible = true  # ВМ может быть прервана для снижения стоимости
  }

  # Метаданные для настройки ВМ при первом запуске
  metadata = {
    ssh-keys  = "ubuntu:${file("id_rsa.pub")}"  # SSH-ключ для доступа к ВМ
    user-data = <<EOF  # Cloud-init конфигурация для автоматической настройки
#cloud-config
# Обновление списка пакетов и системы при первом запуске
package_update: true   # Обновить список доступных пакетов
package_upgrade: true  # Обновить установленные пакеты до последних версий

# Установка необходимых пакетов для работы веб-сервера
packages:
  - nginx    # Веб-сервер
  - ufw      # Брандмауэр
  - curl     # Утилита для HTTP-запросов
  - jq       # Парсер JSON
  - htop     # Монитор системы
  - vim      # Текстовый редактор

# Создание конфигурационных файлов и веб-страниц
write_files:
  # Создание главной страницы веб-сайта с информацией о сервере
  - path: /var/www/html/index.html
    content: |
      <!DOCTYPE html>
      <html>
      <head>
          <title>Сервер vm-${count.index + 1} - Yandex Cloud</title>
          <meta charset="UTF-8">
          <meta name="viewport" content="width=device-width, initial-scale=1.0">
          <style>
              body {
                  font-family: Arial, sans-serif;
                  margin: 0;
                  padding: 20px;
                  background-color: #f5f5f5;
                  color: #333;
              }
              .container {
                  max-width: 800px;
                  margin: 0 auto;
                  background-color: white;
                  padding: 20px;
                  border-radius: 5px;
                  box-shadow: 0 2px 5px rgba(0,0,0,0.1);
              }
              h1 {
                  color: #0077cc;
              }
              .info {
                  margin-top: 20px;
                  padding: 15px;
                  background-color: #e6f7ff;
                  border-left: 5px solid #0077cc;
              }
              .server-info {
                  margin-top: 10px;
                  font-family: monospace;
                  background-color: #f0f0f0;
                  padding: 10px;
                  border-radius: 3px;
              }
          </style>
      </head>
      <body>
          <div class="container">
              <h1>Сервер vm-${count.index + 1}</h1>
              <div class="info">
                  <p>Это тестовая страница для демонстрации отказоустойчивой инфраструктуры в Yandex Cloud.</p>
              </div>
              <div class="server-info">
                  <p><strong>Имя хоста:</strong> $(hostname)</p>
                  <p><strong>IP-адрес:</strong> $(hostname -I | awk '{print $1}')</p>
                  <p><strong>Внешний IP-адрес:</strong> $(curl -s https://ipinfo.io/ip)</p>
                  <p><strong>Дата и время настройки:</strong> $(date)</p>
              </div>
          </div>
      </body>
      </html>
    owner: www-data:www-data  # Владелец файла
    permissions: '0644'       # Права доступа к файлу

  # Конфигурация виртуального хоста Nginx
  - path: /etc/nginx/sites-available/default
    content: |
      server {
          listen 80 default_server;
          listen [::]:80 default_server;

          root /var/www/html;
          index index.html index.htm;

          server_name _;

          location / {
              try_files $uri $uri/ =404;
          }

          # Добавляем заголовки с информацией о сервере
          add_header X-Server-Name "vm-${count.index + 1}";
          add_header X-Server-IP "$remote_addr";
      }
    owner: root:root      # Владелец файла конфигурации
    permissions: '0644'   # Права доступа к конфигурации

  # Скрипт для автоматического обновления информации о сервере на веб-странице
  - path: /usr/local/bin/update-status.sh
    content: |
      #!/bin/bash
      # Скрипт для обновления статуса сервера

      # Получаем текущий IP-адрес
      INTERNAL_IP=$(hostname -I | awk '{print $1}')
      EXTERNAL_IP=$(curl -s https://ipinfo.io/ip)
      HOSTNAME=$(hostname)

      # Обновляем информацию на веб-странице
      sed -i "s/<p><strong>IP-адрес:<\\/strong>.*<\\/p>/<p><strong>IP-адрес:<\\/strong> $INTERNAL_IP<\\/p>/g" /var/www/html/index.html
      sed -i "s/<p><strong>Внешний IP-адрес:<\\/strong>.*<\\/p>/<p><strong>Внешний IP-адрес:<\\/strong> $EXTERNAL_IP<\\/p>/g" /var/www/html/index.html
      sed -i "s/<p><strong>Имя хоста:<\\/strong>.*<\\/p>/<p><strong>Имя хоста:<\\/strong> $HOSTNAME<\\/p>/g" /var/www/html/index.html

      # Обновляем дату и время
      sed -i "s/<p><strong>Дата и время настройки:<\\/strong>.*<\\/p>/<p><strong>Дата и время настройки:<\\/strong> $(date)<\\/p>/g" /var/www/html/index.html
    owner: root:root      # Владелец скрипта
    permissions: '0755'   # Права на выполнение скрипта

# Команды, выполняемые при первом запуске системы
runcmd:
  # Настройка брандмауэра для безопасности
  - ufw default deny incoming   # Запретить все входящие соединения по умолчанию
  - ufw default allow outgoing  # Разрешить все исходящие соединения
  - ufw allow 22/tcp            # Разрешить SSH (порт 22)
  - ufw allow 80/tcp            # Разрешить HTTP (порт 80)
  - ufw --force enable          # Включить брандмауэр без подтверждения

  # Настройка и запуск веб-сервера Nginx
  - systemctl restart nginx     # Перезапустить Nginx с новой конфигурацией
  - systemctl enable nginx      # Включить автозапуск Nginx при загрузке системы

  # Первоначальное обновление информации на веб-странице
  - /usr/local/bin/update-status.sh

  # Настройка автоматического обновления статуса каждые 5 минут
  - echo "*/5 * * * * /usr/local/bin/update-status.sh" | crontab -

# Настройка имени хоста для идентификации сервера
hostname: vm-${count.index + 1}  # Устанавливаем уникальное имя для каждой ВМ
preserve_hostname: false         # Разрешить изменение hostname

# Настройка часового пояса
timezone: Europe/Moscow          # Московское время
EOF
  }
}

# Создание виртуальной частной сети (VPC)
# VPC изолирует наши ресурсы от других пользователей облака
resource "yandex_vpc_network" "network-1" {
  name = "network-otkazoustoichivost"  # Имя сети для проекта отказоустойчивости
}

# Создание подсети внутри VPC
# Подсеть определяет диапазон IP-адресов для наших ВМ
resource "yandex_vpc_subnet" "subnet-1" {
  name           = "subnet1"                    # Имя подсети
  zone           = "ru-central1-a"              # Зона доступности
  network_id     = yandex_vpc_network.network-1.id  # Привязка к созданной сети
  v4_cidr_blocks = ["192.168.10.0/24"]         # Диапазон IP-адресов (254 адреса)
}

# Создание группы целей для балансировщика нагрузки
# Группа целей объединяет наши веб-серверы для распределения трафика
resource "yandex_lb_target_group" "target_group" {
  name      = "my-target-group"  # Имя группы целей
  region_id = "ru-central1"      # Регион размещения

  # Динамическое добавление всех созданных ВМ в группу целей
  dynamic "target" {
    for_each = yandex_compute_instance.vm  # Перебираем все созданные ВМ
    content {
      subnet_id = yandex_vpc_subnet.subnet-1.id                    # Подсеть цели
      address   = target.value.network_interface.0.ip_address       # Внутренний IP-адрес ВМ
    }
  }
}

# Создание сетевого балансировщика нагрузки
# Балансировщик распределяет входящий трафик между веб-серверами
resource "yandex_lb_network_load_balancer" "lb" {
  name = "my-network-lb"  # Имя балансировщика нагрузки

  # Настройка слушателя для HTTP-трафика
  listener {
    name        = "http-listener"  # Имя слушателя
    port        = 80              # Порт для входящих соединений
    target_port = 80              # Порт на целевых серверах
    protocol    = "tcp"           # Протокол (TCP для HTTP)
    external_address_spec {
      ip_version = "ipv4"         # Версия IP-протокола
    }
  }

  # Подключение группы целей к балансировщику
  attached_target_group {
    target_group_id = yandex_lb_target_group.target_group.id  # ID созданной группы целей

    # Настройка проверки работоспособности серверов
    healthcheck {
      name = "http-healthcheck"  # Имя проверки здоровья
      http_options {
        port = 80              # Порт для проверки
        path = "/"             # Путь для HTTP-запроса проверки
      }
    }
  }
}

# Выходные переменные для получения информации о созданной инфраструктуре

# Полная информация о балансировщике нагрузки
output "lb_details" {
  value       = yandex_lb_network_load_balancer.lb  # Все параметры балансировщика
  description = "Полная информация о балансировщике нагрузки"
}

# Список публичных IP-адресов созданных виртуальных машин
output "vm_ips" {
  value       = [for vm in yandex_compute_instance.vm : vm.network_interface.0.nat_ip_address]  # Извлекаем внешние IP всех ВМ
  description = "Публичные IP-адреса виртуальных машин"
}