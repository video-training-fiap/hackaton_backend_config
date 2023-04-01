variable "db_hostname" {
  type        = string
  description = "Database Hostname"
  default = "hackatonprod.cyekrdho7kb5.us-east-1.rds.amazonaws.com"
}

variable "db_port" {
    type        = string
    description = "Database Port"
    default = "3306"
}

variable "db_name" {
    type        = string
    description = "Database Name"
    default = "hackaton"
}

variable "db_username" {
    type        = string
    description = "Database Username"
    default = "admin"
}

variable "db_password" {
    type        = string
    description = "Database password"
    sensitive = true
}

