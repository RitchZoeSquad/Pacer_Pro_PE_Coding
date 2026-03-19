// --- 1. AWS PROVIDER AND DATA ---

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.2"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

// --- 2. NETWORKING RESOURCES (Prerequisites for EC2) ---

resource "aws_vpc" "app_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  tags = {
    Name = "HighLatencyAppVPC"
  }
}

resource "aws_subnet" "app_subnet" {
  vpc_id                  = aws_vpc.app_vpc.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true
  availability_zone       = "${var.aws_region}a"
}

resource "aws_internet_gateway" "app_igw" {
  vpc_id = aws_vpc.app_vpc.id
}

resource "aws_route_table" "app_rt" {
  vpc_id = aws_vpc.app_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.app_igw.id
  }
}

resource "aws_route_table_association" "app_rta" {
  subnet_id      = aws_subnet.app_subnet.id
  route_table_id = aws_route_table.app_rt.id
}

resource "aws_security_group" "app_sg" {
  name        = "app-security-group"
  vpc_id      = aws_vpc.app_vpc.id
  description = "Allows SSH and HTTP/S"

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] 
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

// --- 3. EC2 INSTANCE (The target for automated remediation) ---

resource "aws_instance" "app_server" {
  ami           = var.app_ami_id 
  instance_type = var.instance_type
  subnet_id     = aws_subnet.app_subnet.id
  vpc_security_group_ids = [aws_security_group.app_sg.id]
  
  tags = {
    Name = "High-Latency-App-Server"
  }
}

// --- 4. SNS TOPIC (Notification destination) ---

resource "aws_sns_topic" "remediation_alert_topic" {
  name = "high-latency-remediation-alert"
}

// --- 5. IAM FOR LAMBDA (Least Privilege Implementation) ---

// IAM Role Trust Policy
data "aws_iam_policy_document" "lambda_assume_role_policy" {
  statement {
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "lambda_exec_role" {
  name               = "reboot_lambda_exec_role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role_policy.json
}

// IAM Execution Policy Document
data "aws_iam_policy_document" "lambda_policy_document" {
  statement {
    // CloudWatch Logs Access
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
    resources = [
      "arn:aws:logs:*:*:*"
    ]
  }

  statement {
    // EC2 Reboot Access: Restricted to the specific EC2 instance ARN
    effect = "Allow"
    actions = [
      "ec2:RebootInstances"
    ]
    resources = [
      aws_instance.app_server.arn
    ]
  }

  statement {
    // SNS Publish Access: Restricted to the specific SNS Topic ARN
    effect = "Allow"
    actions = [
      "sns:Publish"
    ]
    resources = [
      aws_sns_topic.remediation_alert_topic.arn
    ]
  }
}

resource "aws_iam_policy" "lambda_execution_policy" {
  name   = "reboot_lambda_execution_policy"
  policy = data.aws_iam_policy_document.lambda_policy_document.json
}

resource "aws_iam_role_policy_attachment" "lambda_policy_attach" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = aws_iam_policy.lambda_execution_policy.arn
}

// --- 6. LAMBDA FUNCTION ---

// Packages the Python code into a zip file
resource "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "${path.module}/../lambda_function/lambda_function.py"
  output_path = "${path.module}/lambda_function.zip"
}

resource "aws_lambda_function" "reboot_lambda" {
  function_name    = "SumoLogicAutoReboot"
  handler          = "lambda_function.lambda_handler"
  runtime          = "python3.10"
  role             = aws_iam_role.lambda_exec_role.arn
  filename         = "${path.module}/lambda_function.zip"
  source_code_hash = resource.archive_file.lambda_zip.output_base64sha256
  timeout          = 30

  // Pass EC2 ID and SNS ARN as environment variables
  environment {
    variables = {
      EC2_INSTANCE_ID = aws_instance.app_server.id
      SNS_TOPIC_ARN   = aws_sns_topic.remediation_alert_topic.arn
    }
  }
}

// --- 7. OUTPUTS ---

output "ec2_instance_id" {
  description = "The ID of the EC2 application instance"
  value       = aws_instance.app_server.id
}

output "sns_topic_arn" {
  description = "The ARN of the SNS topic for notifications"
  value       = aws_sns_topic.remediation_alert_topic.arn
}

output "lambda_function_name" {
  description = "The name of the Lambda function"
  value       = aws_lambda_function.reboot_lambda.function_name
}