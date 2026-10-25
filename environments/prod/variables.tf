variable "folder_id" {
  type        = string
  description = "ID папки Yandex Cloud"
}

variable "project_name" {
  type        = string
  description = "Префикс для имён ресурсов"
  default     = "diploma-prod"
}

variable "zone_a" {
  type        = string
  default     = "ru-central1-a"
  description = "Зона доступности A"
}

variable "zone_b" {
  type        = string
  default     = "ru-central1-b"
  description = "Зона доступности B"
}

# ВАЖНО: сюда вставляем саму строку ключа (начинается с ssh-rsa...), а не путь к файлу
variable "public_ssh_key" {
  type        = string
  description = "Публичный SSH-ключ для пользователя osboxes (целая строка)"
}

variable "service_account_key_file" {
  type        = string
  description = "Путь к JSON-ключу сервисного аккаунта"
}


variable "image_id" {
  type        = string
  description = "Pinned OS image id (controlled upgrades only)"
}

variable "admin_ip" {
  description = "Public IP of administrator workstation (CIDR)"
  type        = string
}
 
