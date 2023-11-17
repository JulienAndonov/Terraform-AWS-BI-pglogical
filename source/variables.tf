variable "region" {
  description = "Defines AWS region"
  type        = string
  default     = "eu-central-1"
}

variable "environment" {
  description = "Name of the environment"
  type        = string
}

variable "database_admin_password" {
  description = "The password for the database"
  type        = string

}

variable "database_admin_username"{
  description = "The username for the database"
  type        = string
}

variable "private_key_path" {
  description = "The path of the private key"
  type        = string
}

variable "public_key" {
  description = "Public key for the session"
  type        = string  
}

variable "ami" {
  description = "AMI for the EC2 image"
  type        = string
  default     = "ami-025d24108be0a614c"
}

variable "source_path" {
  description = "The path for the configuration of the source cluster"
  type        = string
}

variable "database_name" {
  description = "The name of the virtual database we will replicate"
  type        = string
}


variable "rules" {
  type = list(object({
    from_port   = number
    to_port     = number
    protocol    = string
    description = string
  }))
  default = [
    {
      from_port   = 22
      to_port     = 22
      protocol    = "tcp"
      description = "ssh access"
    },
    {
      from_port   = 5432
      to_port     = 5432
      protocol    = "tcp"
      description = "postgresql access"
    },
  ]
}