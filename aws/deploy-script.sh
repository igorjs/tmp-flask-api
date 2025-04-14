#!/bin/bash

# Configuration
LAMBDA_NAME="web-scraper-lambda"
REGION="us-east-1"  # Change to your AWS region
ROLE_ARN="arn:aws:iam::123456789012:role/lambda-execution-role"  # Replace with your role ARN
S3_BUCKET_NAME="your-bucket-name"  # For deployment package if > 50MB
ENVIRONMENT_VARS='{"Variables":{"S3_BUCKET_NAME":"your-bucket-name","S3_JSON_KEY":"scraped_data.json","TARGET_URL":"https://example.com/table-page"}}'
SCHEDULE_EXPRESSION="cron(0 0 * * ? *)"  # Daily at midnight UTC
SCHEDULE_RULE_NAME="daily-web-scraper-rule"

# Ensure script exits on any error
set -e

echo "Starting deployment process..."

# Create a temporary directory for dependencies
TEMP_DIR="$(mktemp -d)"
echo "Created temporary directory: $TEMP_DIR"

# Install dependencies to the temporary directory
echo "Installing dependencies..."
pip install --target="$TEMP_DIR" -r requirements.txt

# Copy lambda function code to the temporary directory
echo "Copying lambda function code..."
cp app.py "$TEMP_DIR/"

# Create the deployment package
echo "Creating deployment package..."
cd "$TEMP_DIR"
zip -r9 "../deployment-package.zip" .
cd -

# Check if deployment package is over 50MB
PACKAGE_SIZE=$(du -m deployment-package.zip | cut -f1)
echo "Deployment package size: ${PACKAGE_SIZE}MB"

if [ $PACKAGE_SIZE -gt 50 ]; then
    echo "Package size exceeds 50MB, uploading to S3..."
    aws s3 cp deployment-package.zip s3://$S3_BUCKET_NAME/
    
    # Create or update the Lambda function using S3
    if aws lambda get-function --function-name $LAMBDA_NAME --region $REGION 2>&1 | grep -q "Function not found"; then
        echo "Creating new Lambda function..."
        aws lambda create-function \
            --function-name $LAMBDA_NAME \
            --runtime python3.9 \
            --role $ROLE_ARN \
            --handler app.scheduled_scraper \
            --code S3Bucket=$S3_BUCKET_NAME,S3Key=deployment-package.zip \
            --environment $ENVIRONMENT_VARS \
            --timeout 30 \
            --region $REGION
    else
        echo "Updating existing Lambda function..."
        aws lambda update-function-code \
            --function-name $LAMBDA_NAME \
            --s3-bucket $S3_BUCKET_NAME \
            --s3-key deployment-package.zip \
            --region $REGION
        
        # Update environment variables
        aws lambda update-function-configuration \
            --function-name $LAMBDA_NAME \
            --environment $ENVIRONMENT_VARS \
            --timeout 30 \
            --region $REGION
    fi
else
    # Create or update the Lambda function directly
    if aws lambda get-function --function-name $LAMBDA_NAME --region $REGION 2>&1 | grep -q "Function not found"; then
        echo "Creating new Lambda function..."
        aws lambda create-function \
            --function-name $LAMBDA_NAME \
            --runtime python3.9 \
            --role $ROLE_ARN \
            --handler app.scheduled_scraper \
            --zip-file fileb://deployment-package.zip \
            --environment $ENVIRONMENT_VARS \
            --timeout 30 \
            --region $REGION
    else
        echo "Updating existing Lambda function..."
        aws lambda update-function-code \
            --function-name $LAMBDA_NAME \
            --zip-file fileb://deployment-package.zip \
            --region $REGION
        
        # Update environment variables
        aws lambda update-function-configuration \
            --function-name $LAMBDA_NAME \
            --environment $ENVIRONMENT_VARS \
            --timeout 30 \
            --region $REGION
    fi
fi

# Clean up
echo "Cleaning up temporary files..."
rm -rf "$TEMP_DIR"
rm -f deployment-package.zip

# Set up CloudWatch Events rule for scheduled execution
echo "Setting up CloudWatch Events schedule..."

# Create or update the rule
aws events put-rule \
    --name $SCHEDULE_RULE_NAME \
    --schedule-expression "$SCHEDULE_EXPRESSION" \
    --state ENABLED \
    --description "Scheduled rule to trigger web scraper lambda" \
    --region $REGION

# Add Lambda as target for the rule
aws events put-targets \
    --rule $SCHEDULE_RULE_NAME \
    --targets "Id"="1","Arn"="arn:aws:lambda:$REGION:$(aws sts get-caller-identity --query 'Account' --output text):function:$LAMBDA_NAME","Input"="{}" \
    --region $REGION

# Add permission for CloudWatch Events to invoke Lambda
# Check if permission already exists to avoid errors
STATEMENT_ID="AllowExecutionFromCloudWatch"
if ! aws lambda get-policy --function-name $LAMBDA_NAME --region $REGION 2>/dev/null | grep -q $STATEMENT_ID; then
    echo "Adding permission for CloudWatch Events to invoke Lambda..."
    aws lambda add-permission \
        --function-name $LAMBDA_NAME \
        --statement-id $STATEMENT_ID \
        --action 'lambda:InvokeFunction' \
        --principal events.amazonaws.com \
        --source-arn $(aws events describe-rule --name $SCHEDULE_RULE_NAME --region $REGION --query 'Arn' --output text) \
        --region $REGION
fi

echo "Deployment and schedule setup completed successfully!"
