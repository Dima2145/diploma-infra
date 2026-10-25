# ---------------- Бастион: снаружи только SSH ----------------
resource "yandex_vpc_security_group" "bastion" {
  name        = "${var.project_name}-sg-bastion"
  description = "Bastion host: SSH only, from admin IP"
  network_id  = yandex_vpc_network.main_net.id

  ingress {
    description    = "SSH from admin IP"
    protocol       = "TCP"
    port           = 22
    v4_cidr_blocks = [var.admin_ip]
  }

  ingress {
    description    = "ICMP from admin IP (debug)"
    protocol       = "ICMP"
    v4_cidr_blocks = [var.admin_ip]
  }

  egress {
    description    = "All outgoing"
    protocol       = "ANY"
    v4_cidr_blocks = ["0.0.0.0/0"]
    from_port      = 0
    to_port        = 65535
  }
}

# ---------------- Web-серверы (приватные) ----------------
resource "yandex_vpc_security_group" "web" {
  name        = "${var.project_name}-sg-web"
  description = "Web servers: HTTP from ALB only, SSH from bastion"
  network_id  = yandex_vpc_network.main_net.id

  ingress {
    description       = "Client traffic from ALB"
    protocol          = "TCP"
    port              = 80
    security_group_id = yandex_vpc_security_group.alb.id
  }

  ingress {
    description       = "Healthchecks from ALB"
    protocol          = "TCP"
    port              = 80
    predefined_target = "loadbalancer_healthchecks"
  }

  ingress {
    description       = "SSH only from bastion"
    protocol          = "TCP"
    port              = 22
    security_group_id = yandex_vpc_security_group.bastion.id
  }

  ingress {
    description       = "Zabbix server to agent (passive checks, 10050)"
    protocol          = "TCP"
    port              = 10050
    security_group_id = yandex_vpc_security_group.zabbix.id
  }

  ingress {
    description    = "ICMP inside VPC (debug)"
    protocol       = "ICMP"
    v4_cidr_blocks = ["10.0.0.0/8"]
  }

  egress {
    description    = "All outgoing (updates via NAT gateway, logs to ES)"
    protocol       = "ANY"
    v4_cidr_blocks = ["0.0.0.0/0"]
    from_port      = 0
    to_port        = 65535
  }
}

# ---------------- Elasticsearch (приватная) ----------------
resource "yandex_vpc_security_group" "elastic" {
  name        = "${var.project_name}-sg-elastic"
  description = "Elasticsearch: API from web/kibana/bastion, SSH from bastion"
  network_id  = yandex_vpc_network.main_net.id

  ingress {
    description       = "Elasticsearch API from web servers (filebeat)"
    protocol          = "TCP"
    port              = 9200
    security_group_id = yandex_vpc_security_group.web.id
  }

  ingress {
    description       = "Elasticsearch API from Kibana"
    protocol          = "TCP"
    port              = 9200
    security_group_id = yandex_vpc_security_group.kibana.id
  }

  ingress {
    description       = "Elasticsearch API from bastion (debug via SSH tunnel)"
    protocol          = "TCP"
    port              = 9200
    security_group_id = yandex_vpc_security_group.bastion.id
  }

  ingress {
    description       = "SSH only from bastion"
    protocol          = "TCP"
    port              = 22
    security_group_id = yandex_vpc_security_group.bastion.id
  }

  ingress {
    description    = "ICMP inside VPC (debug)"
    protocol       = "ICMP"
    v4_cidr_blocks = ["10.0.0.0/8"]
  }

  egress {
    description    = "All outgoing"
    protocol       = "ANY"
    v4_cidr_blocks = ["0.0.0.0/0"]
    from_port      = 0
    to_port        = 65535
  }
}

# ---------------- Zabbix (публичная) ----------------
resource "yandex_vpc_security_group" "zabbix" {
  name        = "${var.project_name}-sg-zabbix"
  description = "Zabbix: web UI from admin, agent data from web"
  network_id  = yandex_vpc_network.main_net.id

  ingress {
    description    = "Zabbix web UI from admin IP"
    protocol       = "TCP"
    port           = 80
    v4_cidr_blocks = [var.admin_ip]
  }

  ingress {
    description       = "SSH only from bastion"
    protocol          = "TCP"
    port              = 22
    security_group_id = yandex_vpc_security_group.bastion.id
  }

  ingress {
    description       = "Zabbix agents to server (active checks, 10051)"
    protocol          = "TCP"
    port              = 10051
    v4_cidr_blocks    = ["10.0.1.0/24", "10.0.2.0/24"]
  }

  ingress {
    description    = "ICMP inside VPC (debug)"
    protocol       = "ICMP"
    v4_cidr_blocks = ["10.0.0.0/8"]
  }

  egress {
    description    = "All outgoing"
    protocol       = "ANY"
    v4_cidr_blocks = ["0.0.0.0/0"]
    from_port      = 0
    to_port        = 65535
  }
}

# ---------------- Kibana (внутренняя, доступ через бастион) ----------------
resource "yandex_vpc_security_group" "kibana" {
  name        = "${var.project_name}-sg-kibana"
  description = "Kibana: UI only via bastion SSH tunnel, SSH from bastion"
  network_id  = yandex_vpc_network.main_net.id

  ingress {
    description       = "Kibana UI via bastion (SSH tunnel)"
    protocol          = "TCP"
    port              = 5601
    security_group_id = yandex_vpc_security_group.bastion.id
  }

  ingress {
    description       = "SSH only from bastion"
    protocol          = "TCP"
    port              = 22
    security_group_id = yandex_vpc_security_group.bastion.id
  }

  ingress {
    description    = "ICMP inside VPC (debug)"
    protocol       = "ICMP"
    v4_cidr_blocks = ["10.0.0.0/8"]
  }

  egress {
    description    = "All outgoing"
    protocol       = "ANY"
    v4_cidr_blocks = ["0.0.0.0/0"]
    from_port      = 0
    to_port        = 65535
  }
}

# ---------------- ALB: слушает 80 из интернета ----------------
resource "yandex_vpc_security_group" "alb" {
  name        = "${var.project_name}-sg-alb"
  description = "ALB: HTTP from internet"
  network_id  = yandex_vpc_network.main_net.id

  ingress {
    description    = "HTTP from internet"
    protocol       = "TCP"
    port           = 80
    v4_cidr_blocks = ["0.0.0.0/0"]
  }

  # HTTPS добавится сюда: port 443, 0.0.0.0/0

  egress {
    description    = "To targets and DNS"
    protocol       = "ANY"
    v4_cidr_blocks = ["0.0.0.0/0"]
    from_port      = 0
    to_port        = 65535
  }
}
