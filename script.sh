#!/bin/bash
set -e

# Load shared variables
source "$(dirname "$0")/config.env"

echo "========== Checking AWS CLI v2 =========="
if ! command -v aws &> /dev/null
then
  echo "AWS CLI not found. Installing..."
  cd /tmp
  curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
  apt install unzip -y
  unzip -q awscliv2.zip
  sudo ./aws/install
else
  echo "AWS CLI already installed."
fi

echo ""
echo "========== Validating AWS Configuration =========="
if ! aws sts get-caller-identity --region "$REGION" >/dev/null 2>&1; then
    echo "❌ AWS CLI is not configured. Run: aws configure"
    exit 1
fi
echo "AWS CLI configured ✓"

echo ""
echo "========== Creating Key Pair =========="
if aws ec2 describe-key-pairs --key-name "$KEY_NAME" --region "$REGION" >/dev/null 2>&1; then
    echo "Key pair '$KEY_NAME' already exists. Skipping..."
else
    aws ec2 create-key-pair \
        --key-name "$KEY_NAME" \
        --region "$REGION" \
        --query "KeyMaterial" --output text > "${KEY_NAME}.pem"

    chmod 400 "${KEY_NAME}.pem"
    echo "Created key pair: $KEY_NAME"
fi

echo ""
echo "========== Creating Security Group =========="
if aws ec2 describe-security-groups --group-names "$SECURITY_GROUP_NAME" --region "$REGION" >/dev/null 2>&1; then
    echo "Security Group '$SECURITY_GROUP_NAME' already exists."
    SG_ID=$(aws ec2 describe-security-groups \
            --group-names "$SECURITY_GROUP_NAME" \
            --region "$REGION" \
            --query "SecurityGroups[0].GroupId" --output text)
else
    SG_ID=$(aws ec2 create-security-group \
        --group-name "$SECURITY_GROUP_NAME" \
        --description "SG for automation script" \
        --region "$REGION" \
        --query 'GroupId' --output text)

    aws ec2 authorize-security-group-ingress \
        --group-id "$SG_ID" \
        --protocol tcp --port 22 --cidr 0.0.0.0/0 \
        --region "$REGION"

    echo "Created Security Group: $SG_ID"
fi

echo ""
echo "========== Launching EC2 Instance =========="
INSTANCE_ID=$(aws ec2 run-instances \
    --image-id "$AMI_ID" \
    --instance-type "$INSTANCE_TYPE" \
    --key-name "$KEY_NAME" \
    --security-group-ids "$SG_ID" \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$INSTANCE_NAME}]" \
    --region "$REGION" \
    --query "Instances[0].InstanceId" --output text)

echo "EC2 Instance ID: $INSTANCE_ID"
echo "Waiting for Public IP..."

while true; do
    PUBLIC_IP=$(aws ec2 describe-instances \
        --instance-id "$INSTANCE_ID" \
        --region "$REGION" \
        --query "Reservations[0].Instances[0].PublicIpAddress" \
        --output text)

    [[ "$PUBLIC_IP" != "None" ]] && break
    sleep 3
done

echo "Public IP: $PUBLIC_IP"

BUCKET_NAME="${BUCKET_NAME_PREFIX}-${RANDOM}"

echo ""
echo "========== Creating S3 Bucket =========="
aws s3 mb "s3://$BUCKET_NAME" --region "$REGION"
echo "Bucket created: $BUCKET_NAME"

echo ""
echo "========== SUMMARY =========="
echo "EC2 Instance : $INSTANCE_ID"
echo "EC2 IP       : $PUBLIC_IP"
echo "Bucket       : $BUCKET_NAME"
echo "=========================================="
