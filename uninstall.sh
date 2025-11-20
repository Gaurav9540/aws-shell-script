#!/bin/bash
set -e

# Load shared variables
source "$(dirname "$0")/config.env"

echo "========== Finding EC2 Instances =========="
INSTANCE_IDS=$(aws ec2 describe-instances \
    --region "$REGION" \
    --filters "Name=tag:Name,Values=$INSTANCE_NAME" \
    --query "Reservations[*].Instances[*].InstanceId" \
    --output text)

if [[ -z "$INSTANCE_IDS" ]]; then
    echo "No EC2 instances found."
else
    echo "Instances found:"
    echo "$INSTANCE_IDS"

    for ID in $INSTANCE_IDS; do
        echo "Terminating $ID ..."
        aws ec2 terminate-instances \
            --instance-ids "$ID" \
            --region "$REGION" >/dev/null

        aws ec2 wait instance-terminated \
            --instance-ids "$ID" \
            --region "$REGION"

        echo "$ID terminated ✓"
    done
fi

echo ""
echo "========== Deleting Security Group =========="
SG_ID=$(aws ec2 describe-security-groups \
    --group-names "$SECURITY_GROUP_NAME" \
    --region "$REGION" \
    --query "SecurityGroups[0].GroupId" \
    --output text 2>/dev/null || true)

if [[ -z "$SG_ID" || "$SG_ID" == "None" ]]; then
    echo "Security group not found."
else
    echo "Deleting SG: $SG_ID"
    aws ec2 delete-security-group --group-id "$SG_ID" --region "$REGION"
    echo "Security Group deleted ✓"
fi

echo ""
echo "========== Deleting Key Pair =========="
if aws ec2 describe-key-pairs --key-name "$KEY_NAME" --region "$REGION" >/dev/null 2>&1; then
    aws ec2 delete-key-pair --key-name "$KEY_NAME" --region "$REGION"
    echo "Key Pair deleted ✓"
fi

[[ -f "${KEY_NAME}.pem" ]] && rm -f "${KEY_NAME}.pem" && echo "Local PEM deleted ✓"

echo ""
echo "========== Deleting S3 Buckets =========="
BUCKETS=$(aws s3api list-buckets \
    --query "Buckets[?starts_with(Name, '$BUCKET_NAME_PREFIX')].Name" \
    --output text)

if [[ -z "$BUCKETS" ]]; then
    echo "No buckets found."
else
    echo "Buckets found:"
    echo "$BUCKETS"

    for B in $BUCKETS; do
        echo "Emptying $B ..."
        aws s3 rm "s3://$B" --recursive --region "$REGION" >/dev/null

        echo "Deleting $B ..."
        aws s3api delete-bucket --bucket "$B" --region "$REGION"
        echo "$B deleted ✓"
    done
fi

echo ""
echo "========== CLEANUP COMPLETE =========="
