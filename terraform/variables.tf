variable "aws_region" {
  description = "The AWS region to deploy resources in."
  type        = string
  default     = "us-east-1"
}

variable "instance_type" {
  description = "EC2 instance type for the application."
  type        = string
  default     = "t2.micro"
}

variable "app_ami_id" {
  description = "AMI ID for the application server (e.g., a standard Amazon Linux 2 AMI). Must be valid for the chosen region."
  type        = string
  default     = "ami-0abcdef1234567890" # Placeholder: Replace with a valid AMI ID for your region
  # Example valid AMIs by region:
  # us-east-1: ami-0c02fb55b7f5ae374 (Amazon Linux 2023)
  # us-west-2: ami-0efcece6bed30fd98 (Amazon Linux 2023)
  # eu-west-1: ami-0d71ea30463e0ff8d (Amazon Linux 2023)
}
