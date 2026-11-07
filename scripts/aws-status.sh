#!/usr/bin/env bash
# Read-only. Prints the Free plan credit balance and anything billable that is still running, so it
# can be run before and after every AWS session and after teardown.
# Usage: scripts/aws-status.sh      (profile eks-demo, region us-east-1; override with AWS_PROFILE / AWS_REGION)
set -uo pipefail
export PATH="${HOME}/.local/bin:${PATH}" AWS_PAGER=""
export AWS_PROFILE="${AWS_PROFILE:-eks-demo}" AWS_REGION="${AWS_REGION:-us-east-1}"

if ! aws sts get-caller-identity >/dev/null 2>&1; then
  echo "Not signed in to AWS. Run: aws login --remote --profile ${AWS_PROFILE}" >&2
  exit 1
fi

echo "== identity"
aws sts get-caller-identity --query Arn --output text
echo "== Free plan"
aws freetier get-account-plan-state --region us-east-1 \
  --query '[accountPlanType,accountPlanStatus,accountPlanRemainingCredits.amount,accountPlanExpirationDate]' --output text |
  awk '{printf "plan=%s status=%s credits_left=%s USD expires=%s\n", $1, $2, $3, $4}'

found=0
check() { # check <label> <output of a list command>
  local label="$1" out="$2"
  if [ -n "${out}" ] && [ "${out}" != "None" ]; then
    echo "!! ${label}:"
    echo "${out}" | sed 's/^/     /'
    found=1
  else
    echo "ok ${label}: none"
  fi
}

echo "== billable resources in ${AWS_REGION}"
check "EKS clusters" "$(aws eks list-clusters --query 'clusters' --output text)"
check "EC2 instances (not terminated)" "$(aws ec2 describe-instances \
  --filters Name=instance-state-name,Values=pending,running,stopping,stopped \
  --query 'Reservations[].Instances[].[InstanceId,InstanceType,State.Name]' --output text)"
check "NAT gateways" "$(aws ec2 describe-nat-gateways --filter Name=state,Values=pending,available \
  --query 'NatGateways[].NatGatewayId' --output text)"
check "Elastic IPs" "$(aws ec2 describe-addresses --query 'Addresses[].[PublicIp,AssociationId]' --output text)"
check "Load balancers (ALB/NLB)" "$(aws elbv2 describe-load-balancers --query 'LoadBalancers[].LoadBalancerName' --output text)"
check "Load balancers (classic)" "$(aws elb describe-load-balancers --query 'LoadBalancerDescriptions[].LoadBalancerName' --output text)"
check "EBS volumes" "$(aws ec2 describe-volumes --query 'Volumes[].[VolumeId,Size,State]' --output text)"
check "VPC endpoints" "$(aws ec2 describe-vpc-endpoints --query 'VpcEndpoints[].VpcEndpointId' --output text)"

echo "== not billable, but shows an unfinished teardown"
check "Non-default VPCs" "$(aws ec2 describe-vpcs --filters Name=is-default,Values=false --query 'Vpcs[].VpcId' --output text)"
echo "== for information"
echo "ECR repositories: $(aws ecr describe-repositories --query 'repositories[].repositoryName' --output text)"

echo
if [ "${found}" -eq 0 ]; then
  echo "ALL CLEAR: nothing billable is running."
else
  echo "SOMETHING IS STILL RUNNING (see the !! lines above)."
fi
