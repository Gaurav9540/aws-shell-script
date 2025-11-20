#!/bin/bash
set -e

# ===================================================
#  VARIABLES (same as creation script)
# ===================================================
INSTANCE_NAME="devops-ec2-instance"
REGION="us-east-1"
KEY_NAME="my-ec2-key"
SECURITY_GROUP_NAME="my-ec2-sg"
BUCKET_NAME_PREFIX="my-devops-bucket"
# ===================================================


echo "========== Finding EC2 Instances =========="

INSTANCE_IDS=$(aws ec2 describe-instances \
    --region $REGION \
    --filters "Name=tag:Name,Values=$INSTANCE_NAME" \
    --query "Reservations[*].Instances[*].InstanceId" \
    --output text)

if [[ -z "$INSTANCE_IDS" ]]; then
    echo "No EC2 instances found with name: $INSTANCE_NAME"
else
    echo "Found Instances:"
    echo "$INSTANCE_IDS"
    echo "Terminating instances..."

    for INSTANCE_ID in $INSTANCE_IDS; do
        echo "Terminating $INSTANCE_ID ..."
        aws ec2 terminate-instances \
            --instance-ids "$INSTANCE_ID" \
            --region $REGION >/dev/null

        echo "Waiting for $INSTANCE_ID to terminate..."
        aws ec2 wait instance-terminated \
            --instance-ids "$INSTANCE_ID" \
            --region $REGION
        echo "$INSTANCE_ID terminated ✓"
    done
fi


echo ""
echo "========== Deleting Security Group =========="

SG_ID=$(aws ec2 describe-security-groups \
    --group-names "$SECURITY_GROUP_NAME" \
    --region $REGION \
    --query "SecurityGroups[0].GroupId" 2>/dev/null || true)

if [[ -z "$SG_ID" || "$SG_ID" == "None" ]]; then
    echo "Security Group '$SECURITY_GROUP_NAME' not found."
else
    echo "Deleting SG: $SG_ID"
    aws ec2 delete-security-group \
        --group-id "$SG_ID" \
        --region $REGION
    echo "Security Group deleted ✓"
fi


echo ""
echo "========== Deleting Key Pair =========="

if aws ec2 describe-key-pairs --key-name "$KEY_NAME" --region $REGION >/dev/null 2>&1; then
    aws ec2 delete-key-pair \
        --key-name "$KEY_NAME" \
        --region $REGION
    echo "Key Pair deleted ✓"
else
    echo "Key Pair '$KEY_NAME' not found."
fi

# Delete local .pem file
if [[ -f "${KEY_NAME}.pem" ]]; then
    rm -f "${KEY_NAME}.pem"
    echo "Local PEM file removed ✓"
fi


echo ""
echo "========== Deleting S3 Buckets =========="

BUCKETS=$(aws s3api list-buckets \
    --query "Buckets[?starts_with(Name, '$BUCKET_NAME_PREFIX')].Name" \
    --output text)

if [[ -z "$BUCKETS" ]]; then
    echo "No S3 buckets found with prefix: $BUCKET_NAME_PREFIX"
else
    echo "Found Buckets:"
    echo "$BUCKETS"

    for BUCKET in $BUCKETS; do
        echo "Emptying bucket: $BUCKET"
        aws s3 rm "s3://$BUCKET" --recursive --region $REGION >/dev/null
      
        echo "Deleting bucket: $BUCKET"
        aws s3api delete-bucket \
            --bucket "$BUCKET" \
            --region $REGION

        echo "Bucket $BUCKET deleted ✓"
    done
fi


echo ""
echo "========== SUMMARY =========="
echo "EC2 Instances  : Deleted (if existed)"
echo "Security Group : Deleted (if existed)"
echo "Key Pair       : Deleted"
echo "S3 Buckets     : Deleted"
echo "Local PEM File : Deleted"
echo "========================================="
echo "Cleanup completed successfully 🧹"
