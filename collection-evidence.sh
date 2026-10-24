
#!/usr/bin/env bash

# Usage:
# ./collect-evidence.sh BUCKET EC2_ADDRESS LAMBDA_URL

if [ "$#" -ne 3 ]; then
    echo "Usage: $0 BUCKET EC2_ADDRESS LAMBDA_URL"
    exit 1
fi

BUCKET="$1"
EC2_ADDRESS="$2"
LAMBDA_URL="$3"
REGION="ap-southeast-2"
OUT="evidence.txt"

# Accept either an IP address or a URL for the EC2 argument.
EC2_HOST="${EC2_ADDRESS#http://}"
EC2_HOST="${EC2_HOST#https://}"
EC2_HOST="${EC2_HOST%%/*}"

# Find the instance ID from its public IPv4 address.
INSTANCE_ID="$(aws ec2 describe-instances \
  --region "$REGION" \
  --filters "Name=ip-address,Values=$EC2_HOST" \
  --query 'Reservations[0].Instances[0].InstanceId' \
  --output text 2>/dev/null)"

if [ "$INSTANCE_ID" = "None" ]; then
    INSTANCE_ID=""
fi

# Find the Lambda function whose Function URL matches the argument.
FUNCTION_NAME=""
for NAME in $(aws lambda list-functions \
    --region "$REGION" \
    --query 'Functions[].FunctionName' \
    --output text 2>/dev/null); do

    URL="$(aws lambda get-function-url-config \
      --region "$REGION" \
      --function-name "$NAME" \
      --query 'FunctionUrl' \
      --output text 2>/dev/null || true)"

    if [ "$URL" = "$LAMBDA_URL" ]; then
        FUNCTION_NAME="$NAME"
        break
    fi
done

# Continue collecting even if an individual AWS command fails.
section() {
    local title="$1"
    shift

    {
        echo
        echo "========== ${title} =========="
        if "$@"; then
            :
        else
            echo "[FAILED] Command failed; collection continued."
        fi
    } >> "$OUT" 2>&1
}

{
    echo "AWS CV Hosting Evidence"
    echo "Collected at: $(date -Is 2>/dev/null || date)"
    echo "Region: $REGION"
    echo "Bucket: $BUCKET"
    echo "EC2 address: $EC2_ADDRESS"
    echo "Lambda URL: $LAMBDA_URL"
} > "$OUT"

section "1. caller" \
  aws sts get-caller-identity --region "$REGION"

section "2. public-access" \
  aws s3api get-public-access-block \
    --bucket "$BUCKET" --region "$REGION"

section "3. versioning" \
  aws s3api get-bucket-versioning \
    --bucket "$BUCKET" --region "$REGION"

section "4. objects" \
  aws s3api list-objects-v2 \
    --bucket "$BUCKET" --prefix "site/" --region "$REGION" \
    --query 'Contents[].{Key:Key,Size:Size}' --output table

section "5. ec2-policy" bash -c '
  ROLE="Lab7-EC2-S3-Role"
  REGION="ap-southeast-2"
  echo "--- Attached policies ---"
  aws iam list-attached-role-policies --role-name "$ROLE"
  echo "--- Inline policies ---"
  aws iam list-role-policies --role-name "$ROLE"
  for P in $(aws iam list-role-policies \
      --role-name "$ROLE" --query "PolicyNames[]" --output text); do
    aws iam get-role-policy --role-name "$ROLE" --policy-name "$P"
  done
'

section "6. lambda-policy" bash -c '
  ROLE="Lab7-Lambda-S3-Role"
  echo "--- Attached policies ---"
  aws iam list-attached-role-policies --role-name "$ROLE"
  echo "--- Inline policies ---"
  aws iam list-role-policies --role-name "$ROLE"
  for P in $(aws iam list-role-policies \
      --role-name "$ROLE" --query "PolicyNames[]" --output text); do
    aws iam get-role-policy --role-name "$ROLE" --policy-name "$P"
  done
'

section "7. security-group" bash -c '
  REGION="ap-southeast-2"
  INSTANCE_ID="$1"
  if [ -z "$INSTANCE_ID" ]; then
    echo "Could not find EC2 instance from the supplied address."
    exit 1
  fi
  aws ec2 describe-instances --region "$REGION" \
    --instance-ids "$INSTANCE_ID" \
    --query "Reservations[].Instances[].SecurityGroups"
' _ "$INSTANCE_ID"

section "8. instance" bash -c '
  REGION="ap-southeast-2"
  INSTANCE_ID="$1"
  if [ -z "$INSTANCE_ID" ]; then
    echo "Could not find EC2 instance from the supplied address."
    exit 1
  fi
  aws ec2 describe-instances --region "$REGION" \
    --instance-ids "$INSTANCE_ID" \
    --query "Reservations[].Instances[].{Id:InstanceId,State:State.Name,Type:InstanceType,PublicIP:PublicIpAddress,IAM:IamInstanceProfile.Arn,Metadata:MetadataOptions.HttpTokens}"
' _ "$INSTANCE_ID"

section "9. endpoints" bash -c '
  EC2_URL="$1"
  LAMBDA_URL="$2"
  echo "--- EC2 endpoint ---"
  curl -sS -L -o /dev/null -w "HTTP %{http_code}\n" "$EC2_URL"
  echo "--- Lambda endpoint ---"
  curl -sS -L -o /dev/null -w "HTTP %{http_code}\n" "$LAMBDA_URL"
  echo "--- Lambda CSS route ---"
  curl -sS -L -o /dev/null -w "HTTP %{http_code}\n" "${LAMBDA_URL%/}/style.css"
  echo "--- Lambda PDF route ---"
  curl -sS -L -o /dev/null -w "HTTP %{http_code}\n" "${LAMBDA_URL%/}/cv.pdf"
  echo "--- Lambda unknown route ---"
  curl -sS -L -o /dev/null -w "HTTP %{http_code}\n" "${LAMBDA_URL%/}/not-a-real-page"
' _ "$EC2_ADDRESS" "$LAMBDA_URL"

section "10. lambda-logs" bash -c '
  REGION="ap-southeast-2"
  FUNCTION_NAME="$1"
  if [ -z "$FUNCTION_NAME" ]; then
    echo "Could not match the supplied URL to a Lambda function."
    exit 1
  fi
  aws logs describe-log-streams --region "$REGION" \
    --log-group-name "/aws/lambda/$FUNCTION_NAME" \
    --order-by LastEventTime --descending --limit 1
' _ "$FUNCTION_NAME"

section "11. log-retention" bash -c '
  REGION="ap-southeast-2"
  FUNCTION_NAME="$1"
  if [ -z "$FUNCTION_NAME" ]; then
    echo "Could not identify the Lambda function."
    exit 1
  fi
  aws logs describe-log-groups --region "$REGION" \
    --log-group-name-prefix "/aws/lambda/$FUNCTION_NAME" \
    --query "logGroups[].{LogGroup:logGroupName,RetentionDays:retentionInDays}"
' _ "$FUNCTION_NAME"

echo
echo "DONE"
