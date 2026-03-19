import json
import os
import boto3
import logging

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize AWS clients
# Boto3 automatically picks up the region from the Lambda environment
ec2_client = boto3.client('ec2')
sns_client = boto3.client('sns')

# Get configuration from environment variables
EC2_INSTANCE_ID = os.environ.get('EC2_INSTANCE_ID')
SNS_TOPIC_ARN = os.environ.get('SNS_TOPIC_ARN')

def lambda_handler(event, context):
    """
    AWS Lambda function triggered by a Sumo Logic webhook.
    It restarts a specified EC2 instance, logs the action, and sends an SNS notification.
    """
    
    logger.info("--- Sumo Logic Alert Triggered ---")
    logger.info(f"Received Event: {json.dumps(event)}") # Log the Sumo Logic payload

    # Input validation
    if not EC2_INSTANCE_ID or not SNS_TOPIC_ARN:
        logger.error("Configuration Error: EC2_INSTANCE_ID or SNS_TOPIC_ARN environment variable is missing.")
        raise Exception("Missing required environment variables.")

    # 1. Restart the specified EC2 instance
    try:
        logger.info(f"Initiating reboot for EC2 instance: {EC2_INSTANCE_ID}")
        
        ec2_client.reboot_instances(
            InstanceIds=[EC2_INSTANCE_ID]
        )
        
        # Log the action
        action_log = f"Successfully initiated reboot for EC2 instance: {EC2_INSTANCE_ID}"
        logger.info(action_log)
        
        # 2. Send SNS notification
        sns_subject = f"REMEDIATION: EC2 {EC2_INSTANCE_ID} Restarted"
        
        # Construct message content
        sns_message = {
            "InstanceID": EC2_INSTANCE_ID,
            "Action": "EC2 Reboot Initiated",
            "TriggerSource": "Sumo Logic Alert",
            "AlertDetails": event # Include the alert payload for context
        }

        sns_client.publish(
            TopicArn=SNS_TOPIC_ARN,
            Message=json.dumps(sns_message, indent=2),
            Subject=sns_subject
        )
        
        logger.info(f"SNS notification successfully sent to topic: {SNS_TOPIC_ARN}")

        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': action_log,
                'status': 'Completed successfully'
            })
        }

    except Exception as e:
        error_message = f"FATAL ERROR: An error occurred during EC2 reboot or SNS publish: {str(e)}"
        logger.error(error_message)
        
        # Attempt to send a failure notification (optional but recommended)
        try:
            sns_client.publish(
                TopicArn=SNS_TOPIC_ARN,
                Message=f"Automated EC2 restart failed for {EC2_INSTANCE_ID}. Error: {str(e)}",
                Subject=f"ERROR: Automated Remediation Failed for {EC2_INSTANCE_ID}"
            )
        except Exception as sns_e:
            logger.error(f"Failed to send failure notification to SNS: {str(sns_e)}")

        raise e # Re-raise the exception to indicate Lambda failure