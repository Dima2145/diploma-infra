# Публичные адреса
output "alb_public_ip" {
  description = "Public IP of Application Load Balancer"
  value       = yandex_alb_load_balancer.web_alb.listener[0].endpoint[0].address[0].external_ipv4_address[0].address
}

output "bastion_public_ip" {
  description = "Public IP of bastion host (jump host)"
  value       = yandex_compute_instance.bastion.network_interface[0].nat_ip_address
}

output "zabbix_public_ip" {
  description = "Public IP of zabbix-01 (web UI, restricted by SG)"
  value       = yandex_compute_instance.zabbix.network_interface[0].nat_ip_address
}

output "kibana_public_ip" {
  description = "Public IP of kibana-01 (UI via bastion SSH tunnel)"
  value       = yandex_compute_instance.kibana.network_interface[0].nat_ip_address
}

# Внутренние адреса (для Ansible inventory по FQDN и отладки)
output "web_01_internal_ip" {
  description = "Internal IP of web-01"
  value       = yandex_compute_instance.web_01.network_interface[0].ip_address
}

output "web_02_internal_ip" {
  description = "Internal IP of web-02"
  value       = yandex_compute_instance.web_02.network_interface[0].ip_address
}

output "elastic_internal_ip" {
  description = "Internal IP of elastic-01"
  value       = yandex_compute_instance.elastic.network_interface[0].ip_address
}

output "kibana_internal_ip" {
  description = "Internal IP of kibana-01"
  value       = yandex_compute_instance.kibana.network_interface[0].ip_address
}

output "zabbix_internal_ip" {
  description = "Internal IP of zabbix-01"
  value       = yandex_compute_instance.zabbix.network_interface[0].ip_address
}
