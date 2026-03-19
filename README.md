# Platform Engineer Coding Test - Solution


https://www.loom.com/share/385bf139bdf94294944994c80de5bad1


## Overview
This repository contains a monitoring and automation solution for automatically detecting and resolving performance issues in a web application. The solution monitors the `/api/data` endpoint for high latency and automatically restarts the EC2 instance when issues are detected.

## Repository Structure

```
.
├── sumo_logic_query.txt    # Sumo Logic query and alert configuration
├── lambda_function/
│   └── lambda_function.py  # AWS Lambda function for automated remediation
├── terraform/
│   ├── main.tf             # Terraform infrastructure configuration
│   └── variables.tf        # Terraform variable definitions
├── .env                    # Environment variables (example)
└── README.md               # This file
```

## Solution Components

### Part 1: Sumo Logic Query and Alert

**File:** `sumo_logic_query.txt`

**Query Logic:**
- Filters logs for the `/api/data` endpoint where response time exceeds 3 seconds
- Uses a 10-minute sliding window to aggregate results
- Triggers when more than 5 high-latency entries are detected

**Alert Configuration:**
- **Type:** Scheduled Search with Webhook
- **Frequency:** Every 10 minutes
- **Time Range:** Last 10 minutes (-10m)
- **Trigger Condition:** Number of results > 0
- **Action:** Webhook to Lambda function URL

**Assumptions:**
- Response time is measured in milliseconds (query uses `> 3000`)
- If your logs use seconds, change the query to `response_time > 3`
- Webhook integration requires AWS API Gateway or Lambda Function URL

### Part 2: AWS Lambda Function

**File:** `lambda_function/lambda_function.py`

**Functionality:**
1. Receives webhook trigger from Sumo Logic alert
2. Reboots the specified EC2 instance using `ec2:RebootInstances`
3. Logs all actions to CloudWatch Logs
4. Sends notification to SNS topic with alert details
5. Implements error handling with fallback notifications

**Key Features:**
- Environment-based configuration (EC2_INSTANCE_ID, SNS_TOPIC_ARN)
- Comprehensive logging for debugging
- Error handling with SNS notifications on failure
- Clean separation of concerns

**Testing:**
You can test the Lambda function manually using this test event:
```json
{
  "SearchName": "High Latency Alert",
  "SearchDescription": "Response time exceeded threshold",
  "NumRawResults": 7,
  "TimeRange": "10m"
}
```

### Part 3: Infrastructure as Code (Terraform)

**Files:** `terraform/main.tf`, `terraform/variables.tf`

**Resources Created:**
1. **VPC & Networking**
   - VPC (10.0.0.0/16)
   - Public subnet
   - Internet Gateway
   - Route table

2. **EC2 Instance**
   - Application server that will be monitored/restarted
   - Configurable instance type (default: t2.micro)

3. **SNS Topic**
   - Notification destination for remediation alerts

4. **Lambda Function**
   - Auto-remediation function
   - Configured with environment variables
   - Least privilege IAM permissions

5. **IAM Roles & Policies**
   - Lambda execution role with least privilege:
     - CloudWatch Logs access
     - EC2 reboot permission (restricted to specific instance)
     - SNS publish permission (restricted to specific topic)

**Security - Least Privilege Implementation:**
- IAM policies scope permissions to specific resource ARNs
- Lambda can only reboot the specific EC2 instance created by this configuration
- Lambda can only publish to the specific SNS topic created by this configuration
- CloudWatch Logs permissions limited to log creation/writing

## Deployment Instructions

### Prerequisites
- AWS CLI configured with appropriate credentials
- Terraform installed (v1.0+)
- Valid AMI ID for your target region

### Step 1: Update Variables
Edit `terraform/variables.tf` and set a valid AMI ID for your region:
```hcl
variable "app_ami_id" {
  default = "ami-xxxxxxxxxxxxxxxxx"  # Replace with valid AMI
}
```

Example AMIs:
- **us-east-1:** ami-0c02fb55b7f5ae374 (Amazon Linux 2023)
- **us-west-2:** ami-0efcece6bed30fd98 (Amazon Linux 2023)
- **eu-west-1:** ami-0d71ea30463e0ff8d (Amazon Linux 2023)

### Step 2: Deploy Infrastructure
```bash
cd terraform
terraform init
terraform plan
terraform apply
```

### Step 3: Note the Outputs
After deployment, Terraform will output:
- `ec2_instance_id` - The EC2 instance being monitored
- `sns_topic_arn` - SNS topic for notifications
- `lambda_function_name` - Name of the Lambda function

### Step 4: Configure Lambda Trigger
You need to set up a way for Sumo Logic to trigger the Lambda:

**Option A: Lambda Function URL (Recommended for testing)**
```bash
aws lambda create-function-url-config \
  --function-name SumoLogicAutoReboot \
  --auth-type NONE
```

**Option B: API Gateway (Recommended for production)**
Create an API Gateway REST API with a POST method that triggers the Lambda function.

### Step 5: Configure Sumo Logic Webhook
1. Create a Scheduled Search in Sumo Logic using the query from `sumo_logic_query.txt`
2. Configure the webhook to point to your Lambda Function URL or API Gateway endpoint
3. Set the alert to run every 10 minutes

### Step 6: Subscribe to SNS Topic (Optional)
```bash
aws sns subscribe \
  --topic-arn <sns_topic_arn_from_output> \
  --protocol email \
  --notification-endpoint your-email@example.com
```

## Testing

### Manual Lambda Test
1. Go to AWS Lambda Console
2. Select the `SumoLogicAutoReboot` function
3. Create a test event with this payload:
```json
{
  "SearchName": "Manual Test",
  "NumRawResults": 10
}
```
4. Execute the test
5. Verify:
   - EC2 instance reboots
   - CloudWatch Logs show execution details
   - SNS notification is sent

### End-to-End Test
1. Ensure Sumo Logic is sending logs from your application
2. Simulate high latency on the `/api/data` endpoint
3. Wait for the alert to trigger (up to 10 minutes)
4. Verify automated remediation occurs

## Assumptions and Deviations

### Assumptions Made:
1. **Response Time Units:** Assumed response_time field is in milliseconds (3000ms = 3s)
2. **Log Format:** Assumed logs contain a `response_time` field accessible in Sumo Logic
3. **AWS Region:** Default deployment to us-east-1 (configurable via variables)
4. **EC2 State:** Assumed the EC2 instance will be running when reboot is triggered
5. **Webhook Delivery:** Assumed Sumo Logic webhook will send JSON payload to Lambda

### Deviations from Requirements:
- **Lambda Trigger Method:** Requirements mention Lambda triggered by Sumo Logic but don't specify the integration method. Solution requires either Lambda Function URL or API Gateway (not included in Terraform to keep scope focused).

### Security Considerations:
- **SSH Access:** Security group allows SSH from 0.0.0.0/0 for testing purposes. In production, restrict to specific IP ranges.
- **Lambda Function URL:** If using Function URL with `auth-type NONE`, consider adding authorization or using API Gateway with authentication.

## Troubleshooting

### Lambda Function Errors
Check CloudWatch Logs:
```bash
aws logs tail /aws/lambda/SumoLogicAutoReboot --follow
```

### EC2 Not Rebooting
Verify IAM permissions:
```bash
aws lambda get-function --function-name SumoLogicAutoReboot
aws iam get-role-policy --role-name reboot_lambda_exec_role --policy-name reboot_lambda_execution_policy
```

### SNS Not Sending
Check SNS topic subscriptions:
```bash
aws sns list-subscriptions-by-topic --topic-arn <your-topic-arn>
```

## Cleanup

To destroy all resources:
```bash
cd terraform
terraform destroy
```

## Screen and Audio Recordings

**Note:** Screen recordings should include:
1. Part 1: Implementing the Sumo Logic query and configuring the alert
2. Part 2: Deploying and testing the Lambda function
3. Part 3: Deploying infrastructure with Terraform and verifying resources

[Add links to your recordings here]
- Part 1 Recording: [Link to recording]
- Part 2 Recording: [Link to recording]
- Part 3 Recording: [Link to recording]

## Contact

For questions or clarifications about this implementation, please refer to the assumptions section above.
