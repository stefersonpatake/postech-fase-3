variable "identifier" {
  description = "Identificador da instância (ex.: togglemaster-auth)"
  type        = string
}

variable "db_name" {
  description = "Nome do banco inicial"
  type        = string
}

variable "username" {
  description = "Usuário master"
  type        = string
}

variable "password" {
  description = "Senha do usuário master"
  type        = string
  sensitive   = true
}

variable "engine_version" {
  description = "Versão major do PostgreSQL"
  type        = string
  default     = "17"
}

variable "instance_class" {
  type    = string
  default = "db.t3.micro"
}

variable "allocated_storage" {
  description = "Armazenamento em GB"
  type        = number
  default     = 20
}

variable "db_subnet_group_name" {
  type = string
}

variable "vpc_security_group_ids" {
  type = list(string)
}
