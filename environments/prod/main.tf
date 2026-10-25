terraform {
  required_providers {
    yandex = {
      source  = "yandex-cloud/yandex"
      version = "0.238.0"
    }
  }
}

provider "yandex" {
  folder_id                = var.folder_id
  service_account_key_file = var.service_account_key_file
}

# Создаём сеть
resource "yandex_vpc_network" "main_net" {
  name = "${var.project_name}-network"
}

# NAT-шлюз: даёт приватным ВМ исходящий интернет без публичных IP
resource "yandex_vpc_gateway" "nat_gw" {
  name = "diploma-prod-nat-gw"
  shared_egress_gateway {}
}

# Таблица маршрутизации: весь трафик наружу — через шлюз
resource "yandex_vpc_route_table" "nat_rt" {
  network_id = yandex_vpc_network.main_net.id

  static_route {
    destination_prefix = "0.0.0.0/0"
    gateway_id         = yandex_vpc_gateway.nat_gw.id
  }
}

# Подсеть в зоне A
resource "yandex_vpc_subnet" "zone_a" {
  name           = "${var.project_name}-subnet-a"
  network_id     = yandex_vpc_network.main_net.id
  v4_cidr_blocks = ["10.0.1.0/24"]
  zone           = var.zone_a
  route_table_id = yandex_vpc_route_table.nat_rt.id
}

# Подсеть в зоне B
resource "yandex_vpc_subnet" "zone_b" {
  name           = "${var.project_name}-subnet-b"
  network_id     = yandex_vpc_network.main_net.id
  v4_cidr_blocks = ["10.0.2.0/24"]
  zone           = var.zone_b
  route_table_id = yandex_vpc_route_table.nat_rt.id
}

# Статический публичный IP для бастиона — закреплён навсегда,
# переживает стоп/старт и пересоздание ВМ
resource "yandex_vpc_address" "bastion_ip" {
  name = "diploma-prod-bastion-ip"

  external_ipv4_address {
    zone_id = var.zone_a
  }
}

# Bastion Host в зоне A
resource "yandex_compute_instance" "bastion" {
  name        = "bastion-host"
  zone        = var.zone_a
  platform_id = "standard-v3"

  resources {
    cores  = 2
    memory = 2
  }

  boot_disk {
    initialize_params {
      image_id = var.image_id
    }
  }

  network_interface {
    subnet_id          = yandex_vpc_subnet.zone_a.id
    nat                = true
    nat_ip_address     = yandex_vpc_address.bastion_ip.external_ipv4_address[0].address
    security_group_ids = [yandex_vpc_security_group.bastion.id]
  }




  metadata = {
    ssh-keys           = "osboxes:${var.public_ssh_key}"
    serial-port-enable = "1"
    user-data          = <<-EOF
      #cloud-config
      ssh_pwauth: false
      users:
        - name: osboxes
          lock_passwd: true
          sudo: ALL=(ALL) NOPASSWD:ALL
          shell: /bin/bash
          ssh_authorized_keys:
            - ${var.public_ssh_key}
    EOF
  }
}

# Веб-сервер 1 в зоне A
resource "yandex_compute_instance" "web_01" {
  name     = "web-01"
  hostname = "web-01"
  zone     = var.zone_a
  platform_id = "standard-v3"

  resources {
    cores  = 2
    memory = 2
  }

  boot_disk {
    initialize_params {
      image_id = var.image_id
    }
  }

  network_interface {
    subnet_id          = yandex_vpc_subnet.zone_a.id
    nat                = false
    security_group_ids = [yandex_vpc_security_group.web.id]
  }

  metadata = {
    ssh-keys           = "osboxes:${var.public_ssh_key}"
    serial-port-enable = "1"
    user-data          = <<-EOF
      #cloud-config
      ssh_pwauth: false
      users:
        - name: osboxes
          lock_passwd: true
          sudo: ALL=(ALL) NOPASSWD:ALL
          shell: /bin/bash
          ssh_authorized_keys:
            - ${var.public_ssh_key}
    EOF
  }
}

# Веб-сервер 2 в зоне B (для отказоустойчивости)
resource "yandex_compute_instance" "web_02" {
  name     = "web-02"
  hostname = "web-02"
  zone     = var.zone_b
  platform_id = "standard-v3"

  resources {
    cores  = 2
    memory = 2
  }

  boot_disk {
    initialize_params {
      image_id = var.image_id
    }
  }

  network_interface {
    subnet_id          = yandex_vpc_subnet.zone_b.id
    nat                = false
    security_group_ids = [yandex_vpc_security_group.web.id]
  }

  metadata = {
    ssh-keys           = "osboxes:${var.public_ssh_key}"
    serial-port-enable = "1"
    user-data          = <<-EOF
      #cloud-config
      ssh_pwauth: false
      users:
        - name: osboxes
          lock_passwd: true
          sudo: ALL=(ALL) NOPASSWD:ALL
          shell: /bin/bash
          ssh_authorized_keys:
            - ${var.public_ssh_key}
    EOF
  }
}

# Zabbix
resource "yandex_compute_instance" "zabbix" {
  name        = "zabbix-01"
  hostname    = "zabbix-01"
  zone        = var.zone_a
  platform_id = "standard-v3"

  resources {
    cores  = 2
    memory = 4
    core_fraction = 20
  }

  boot_disk {
    initialize_params {
      image_id = var.image_id
      size     = 12 # Zabbix с БД любит объём, 12 ГБ минимум
    }
  }

  network_interface {
    subnet_id          = yandex_vpc_subnet.zone_a.id
    nat                = true
    security_group_ids = [yandex_vpc_security_group.zabbix.id]
  }

  metadata = {
    ssh-keys           = "osboxes:${var.public_ssh_key}"
    serial-port-enable = "1"
    user-data          = <<-EOF
      #cloud-config
      ssh_pwauth: false
      users:
        - name: osboxes
          lock_passwd: true
          sudo: ALL=(ALL) NOPASSWD:ALL
          shell: /bin/bash
          ssh_authorized_keys:
            - ${var.public_ssh_key}
    EOF
  }
}

# Target Group: наши два веб-сервера
resource "yandex_alb_target_group" "web_tg" {
  name = "web-target-group"

  target {
    subnet_id  = yandex_vpc_subnet.zone_a.id
    ip_address = yandex_compute_instance.web_01.network_interface.0.ip_address
  }

  target {
    subnet_id  = yandex_vpc_subnet.zone_b.id
    ip_address = yandex_compute_instance.web_02.network_interface.0.ip_address
  }
}

# Backend Group с healthcheck: корень /, порт 80, HTTP
resource "yandex_alb_backend_group" "web_bg" {
  name = "web-backend-group"

  http_backend {
    name             = "web-backend"
    weight           = 1
    port             = 80
    target_group_ids = [yandex_alb_target_group.web_tg.id]

    healthcheck {
      timeout             = "2s"
      interval            = "5s"
      healthy_threshold   = 2
      unhealthy_threshold = 5

      http_healthcheck {
        path = "/"
      }
    }
  }
}

# HTTP Router
resource "yandex_alb_http_router" "web_router" {
  name = "web-http-router"
}

# Virtual Host: путь / → backend group
resource "yandex_alb_virtual_host" "web_vhost" {
  name           = "web-vhost"
  http_router_id = yandex_alb_http_router.web_router.id

  route {
    name = "web-route"

    http_route {
      http_route_action {
        backend_group_id = yandex_alb_backend_group.web_bg.id
      }
    }
  }
}

# Application Load Balancer: listener типа AUTO, порт 80
resource "yandex_alb_load_balancer" "web_alb" {
  name               = "web-alb"
  network_id         = yandex_vpc_network.main_net.id
  security_group_ids = [yandex_vpc_security_group.alb.id]

  allocation_policy {
    location {
      zone_id   = var.zone_a
      subnet_id = yandex_vpc_subnet.zone_a.id
    }
    location {
      zone_id   = var.zone_b
      subnet_id = yandex_vpc_subnet.zone_b.id
    }
  }

  listener {
    name = "http-80"

    endpoint {
      address {
        external_ipv4_address {}
      }
      ports = [80]
    }

    http {
      handler {
        http_router_id = yandex_alb_http_router.web_router.id
      }
    }
  }
}

# Elasticsearch — приватная ВМ (логи)
resource "yandex_compute_instance" "elastic" {
  name        = "elastic-01"
  hostname    = "elastic-01"
  zone        = var.zone_a
  platform_id = "standard-v3"

  resources {
    cores         = 2
    memory        = 4
    core_fraction = 20
  }

  boot_disk {
    initialize_params {
      image_id = var.image_id
      size     = 15
    }
  }

  network_interface {
    subnet_id          = yandex_vpc_subnet.zone_a.id
    nat                = false
    security_group_ids = [yandex_vpc_security_group.elastic.id]
  }

  metadata = {
    ssh-keys           = "osboxes:${var.public_ssh_key}"
    serial-port-enable = "1"
    user-data          = <<-EOF
      #cloud-config
      ssh_pwauth: false
      users:
        - name: osboxes
          lock_passwd: true
          sudo: ALL=(ALL) NOPASSWD:ALL
          shell: /bin/bash
          ssh_authorized_keys:
            - ${var.public_ssh_key}
    EOF
  }
}

# Kibana — публичная ВМ (визуализация логов)
resource "yandex_compute_instance" "kibana" {
  name        = "kibana-01"
  hostname    = "kibana-01"
  zone        = var.zone_a
  platform_id = "standard-v3"

  resources {
    cores         = 2
    memory        = 4
    core_fraction = 20
  }

  boot_disk {
    initialize_params {
      image_id = var.image_id
      size     = 12
    }
  }

  network_interface {
    subnet_id          = yandex_vpc_subnet.zone_a.id
    nat                = true
    security_group_ids = [yandex_vpc_security_group.kibana.id]
  }

  metadata = {
    ssh-keys           = "osboxes:${var.public_ssh_key}"
    serial-port-enable = "1"
    user-data          = <<-EOF
      #cloud-config
      ssh_pwauth: false
      users:
        - name: osboxes
          lock_passwd: true
          sudo: ALL=(ALL) NOPASSWD:ALL
          shell: /bin/bash
          ssh_authorized_keys:
            - ${var.public_ssh_key}
    EOF
  }
}

# Резервное копирование: ежедневные снимки дисков всех ВМ, хранение 7 дней
resource "yandex_compute_snapshot_schedule" "daily" {
  name = "diploma-daily-snapshots"

  schedule_policy {
    expression = "0 0 ? * *" # каждый день в 00:00 UTC (03:00 по МСК)
  }

  retention_period = "168h0m0s" # 7 суток, старые снимки удаляются автоматически

  snapshot_spec {
    description = "Daily backup by Terraform schedule"
  }

  disk_ids = [
    yandex_compute_instance.bastion.boot_disk[0].disk_id,
    yandex_compute_instance.web_01.boot_disk[0].disk_id,
    yandex_compute_instance.web_02.boot_disk[0].disk_id,
    yandex_compute_instance.zabbix.boot_disk[0].disk_id,
    yandex_compute_instance.elastic.boot_disk[0].disk_id,
    yandex_compute_instance.kibana.boot_disk[0].disk_id,
  ]
}
