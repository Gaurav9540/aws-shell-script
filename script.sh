#!/bin/bash
set -e

# ===================================================
#  VARIABLES
# ===================================================
INSTANCE_NAME="devops-ec2-instance"
REGION="us-east-1"
INSTANCE_TYPE="t3.small"
AMI_ID="ami-0ecb62995f68bb549"  # Ubuntu 22.04
KEY_NAME="my-ec2-key"
SECURITY_GROUP_NAME="my-ec2-sg"
BUCKET_NAME="my-devops-bucket-$RANDOM"
# ===================================================

echo "========== Checking AWS CLI v2 =========="
if ! command -v aws &> /dev/null
then
  echo "AWS CLI not found. Installing v2..."
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
if ! aws sts get-caller-identity --region $REGION >/dev/null 2>&1; then
    echo "❌ AWS CLI is not configured!"
    echo "Run: aws configure"
    exit 1
fi
echo "AWS CLI configured ✓"

echo ""
echo "========== Creating Key Pair =========="
if aws ec2 describe-key-pairs --key-name "$KEY_NAME" --region $REGION >/dev/null 2>&1; then
    echo "Key pair '$KEY_NAME' already exists. Skipping..."
else
    aws ec2 create-key-pair \
        --region $REGION \
        --key-name "$KEY_NAME" \
        --query "KeyMaterial" --output text > "${KEY_NAME}.pem"

    chmod 400 "${KEY_NAME}.pem"
    echo "Created key pair: $KEY_NAME"
fi

echo ""
echo "========== Creating Security Group =========="
if aws ec2 describe-security-groups --group-names "$SECURITY_GROUP_NAME" --region $REGION >/dev/null 2>&1; then
    echo "Security Group '$SECURITY_GROUP_NAME' already exists. Fetching ID..."
    SG_ID=$(aws ec2 describe-security-groups \
            --group-names "$SECURITY_GROUP_NAME" \
            --region $REGION --query "SecurityGroups[0].GroupId" --output text)
else
    SG_ID=$(aws ec2 create-security-group \
        --group-name "$SECURITY_GROUP_NAME" \
        --description "EC2 SG for automation script" \
        --region $REGION \
        --query 'GroupId' --output text)

    aws ec2 authorize-security-group-ingress \
        --group-id "$SG_ID" \
        --protocol tcp --port 22 --cidr 0.0.0.0/0 \
        --region $REGION

    echo "Security Group created: $SG_ID"
fi

echo ""
echo "========== Launching EC2 Instance =========="
INSTANCE_ID=$(aws ec2 run-instances \
    --image-id "$AMI_ID" \
    --instance-type "$INSTANCE_TYPE" \
    --key-name "$KEY_NAME" \
    --security-group-ids "$SG_ID" \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$INSTANCE_NAME}]"
    --region $REGION \
    --query "Instances[0].InstanceId" --output text)

echo "EC2 Instance created: $INSTANCE_ID"
echo "Waiting for Public IP..."

# Wait until instance gets IP
while true; do
    PUBLIC_IP=$(aws ec2 describe-instances \
        --instance-id "$INSTANCE_ID" \
        --region $REGION \
        --query "Reservations[0].Instances[0].PublicIpAddress" \
        --output text)

    if [[ "$PUBLIC_IP" != "None" ]]; then
        break
    fi
    sleep 3
done

echo "Public IP Allocated: $PUBLIC_IP"

echo ""
echo "========== Creating S3 Bucket =========="
aws s3 mb "s3://$BUCKET_NAME" --region $REGION
echo "S3 Bucket created: $BUCKET_NAME"

echo ""
echo "========== SUMMARY =========="
echo "EC2 Instance ID : $INSTANCE_ID"
echo "EC2 Public IP   : $PUBLIC_IP"
echo "S3 Bucket       : $BUCKET_NAME"
echo "========================================="
echo "Resources created successfully 🚀"
