#!/bin/bash
set -e

# ===================================================
#  VARIABLES (EDIT THESE BEFORE RUNNING)
# ===================================================
REGION="us-east-1"           
INSTANCE_TYPE="t3.small"
AMI_ID="ami-0ecb62995f68bb549" 
KEY_NAME="my-ec2-key"          
SECURITY_GROUP_NAME="my-ec2-sg"
BUCKET_NAME="my-devops-bucket-$RANDOM"
# ===================================================


echo "========== Checking AWS CLI =========="
if ! command -v aws &> /dev/null
then
  echo "AWS CLI not found. Installing..."
  sudo apt update -y
  sudo apt install awscli -y
else
  echo "AWS CLI already installed."
fi


echo "========== Validating AWS Configuration =========="
if ! aws sts get-caller-identity --region $REGION >/dev/null 2>&1; then
    echo "❌ AWS CLI is not configured!"
    echo "Run: aws configure"
    exit 1
fi
echo "AWS CLI configured ✓"


echo "========== Creating Key Pair =========="
if aws ec2 describe-key-pairs --key-name "$KEY_NAME" --region $REGION >/dev/null 2>&1; then
    echo "Key pair '$KEY_NAME' already exists. Skipping..."
else
    aws ec2 create-key-pair --region $REGION --key-name "$KEY_NAME" \
        --query "KeyMaterial" --output text > "${KEY_NAME}.pem"
    chmod 400 "${KEY_NAME}.pem"
    echo "Created key pair: $KEY_NAME"
fi


echo "========== Creating Security Group =========="
SG_ID=$(aws ec2 create-security-group \
    --group-name "$SECURITY_GROUP_NAME" \
    --description "EC2 SG for auto creation script" \
    --region $REGION \
    --query 'GroupId' --output text)

echo "Allowing SSH on port 22"
aws ec2 authorize-security-group-ingress \
    --group-id "$SG_ID" \
    --protocol tcp --port 22 --cidr 0.0.0.0/0 \
    --region $REGION

echo "Security Group created: $SG_ID"


echo "========== Launching EC2 Instance =========="
INSTANCE_ID=$(aws ec2 run-instances \
    --image-id "$AMI_ID" \
    --instance-type "$INSTANCE_TYPE" \
    --key-name "$KEY_NAME" \
    --security-group-ids "$SG_ID" \
    --region $REGION \
    --query "Instances[0].InstanceId" --output text)

echo "EC2 Instance created: $INSTANCE_ID"

echo "Waiting for instance to get Public IP..."
sleep 10

PUBLIC_IP=$(aws ec2 describe-instances \
    --instance-id "$INSTANCE_ID" \
    --region $REGION \
    --query "Reservations[0].Instances[0].PublicIpAddress" \
    --output text)

echo "Public IP Allocated: $PUBLIC_IP"


echo "========== Creating S3 Bucket =========="
aws s3 mb "s3://$BUCKET_NAME" --region $REGION
echo "S3 Bucket created: $BUCKET_NAME"


echo "========== SUMMARY =========="
echo "EC2 Instance ID : $INSTANCE_ID"
echo "EC2 Public IP   : $PUBLIC_IP"
echo "S3 Bucket       : $BUCKET_NAME"
echo "========================================="
echo "Resources created successfully 🚀"
