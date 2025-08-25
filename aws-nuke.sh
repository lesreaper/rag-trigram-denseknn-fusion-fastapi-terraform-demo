#!/usr/bin/env bash
set -u
# Don't set -e so we can keep going even if some deletions fail due to deps.

PROFILE=
REGION=
PREFIX=   # SAFE GUARD. Set "" only if you truly want to delete *everything*.

echo "==== AWS Nuke Script ===="
echo "Profile: $PROFILE   Region: $REGION   Prefix filter: '${PREFIX}'"
read -p "Proceed with destructive cleanup? [y/N] " yn
[[ ${yn:-N} =~ ^[Yy]$ ]] || { echo "Aborted."; exit 1; }

ts() { date +"%Y-%m-%d %H:%M:%S"; }
say() { echo "[$(ts)] $*"; }

########################################
# Helpers
########################################

delete_s3_bucket() {
  local b="$1"
  say "Emptying & deleting S3 bucket: $b"
  # Try multi-region/object versions delete where applicable
  aws s3 rm "s3://$b" --recursive --profile "$PROFILE" --region "$REGION" >/dev/null 2>&1 || true
  # Versioned buckets: remove versions & delete markers
  ids=$(aws s3api list-object-versions --bucket "$b" --profile "$PROFILE" --region "$REGION" --query '[Versions,DeleteMarkers][][].{Key:Key,VersionId:VersionId}' --output json 2>/dev/null)
  if [[ "$ids" != "null" && "$ids" != "" ]]; then
    echo "$ids" | jq -c '.[]' 2>/dev/null | while read -r row; do
      key=$(echo "$row" | jq -r '.Key'); ver=$(echo "$row" | jq -r '.VersionId')
      aws s3api delete-object --bucket "$b" --key "$key" --version-id "$ver" --profile "$PROFILE" --region "$REGION" >/dev/null 2>&1 || true
    done
  fi
  aws s3api delete-bucket --bucket "$b" --profile "$PROFILE" --region "$REGION" >/dev/null 2>&1 || true
}

########################################
# 0) ECR repos (images + repo)
########################################
say "--- ECR repositories ---"
ECR_REPOS=$(aws ecr describe-repositories --profile "$PROFILE" --region "$REGION" \
  --query "repositories[?contains(repositoryName, \`${PREFIX}\`)].repositoryName" --output text 2>/dev/null)
if [[ -n "$ECR_REPOS" ]]; then
  say "Found: $ECR_REPOS"
  read -p "Delete ECR repos and all images? [y/N] " yn
  if [[ $yn =~ ^[Yy]$ ]]; then
    for repo in $ECR_REPOS; do
      say "Deleting images in $repo"
      IMG_IDS=$(aws ecr list-images --repository-name "$repo" --profile "$PROFILE" --region "$REGION" \
        --query 'imageIds[*]' --output json)
      if [[ $(echo "$IMG_IDS" | jq 'length') -gt 0 ]]; then
        aws ecr batch-delete-image --repository-name "$repo" \
          --image-ids "$IMG_IDS" --profile "$PROFILE" --region "$REGION" >/dev/null 2>&1 || true
      fi
      say "Deleting repo $repo"
      aws ecr delete-repository --repository-name "$repo" --force --profile "$PROFILE" --region "$REGION" >/dev/null 2>&1 || true
    done
  fi
else
  say "No ECR repos with prefix '${PREFIX}'."
fi

########################################
# 1) ECS services & clusters
########################################
say "--- ECS clusters/services ---"
CLUSTERS=$(aws ecs list-clusters --profile "$PROFILE" --region "$REGION" --query 'clusterArns' --output text 2>/dev/null)
# limit by prefix where possible
FILTERED_CLUSTERS=""
for c in $CLUSTERS; do
  name="${c##*/}"
  if [[ -z "$PREFIX" || "$name" == *"$PREFIX"* ]]; then
    FILTERED_CLUSTERS="$FILTERED_CLUSTERS $c"
  fi
done

if [[ -n "${FILTERED_CLUSTERS// }" ]]; then
  say "Clusters: $FILTERED_CLUSTERS"
  read -p "Delete ECS services and clusters? [y/N] " yn
  if [[ $yn =~ ^[Yy]$ ]]; then
    for cluster in $FILTERED_CLUSTERS; do
      SERVICES=$(aws ecs list-services --cluster "$cluster" --profile "$PROFILE" --region "$REGION" --query 'serviceArns' --output text 2>/dev/null)
      for svc in $SERVICES; do
        say "Deleting ECS Service $svc"
        aws ecs delete-service --cluster "$cluster" --service "$svc" --force --profile "$PROFILE" --region "$REGION" >/dev/null 2>&1 || true
      done
      say "Deleting ECS Cluster $cluster"
      aws ecs delete-cluster --cluster "$cluster" --profile "$PROFILE" --region "$REGION" >/dev/null 2>&1 || true
    done
  fi
else
  say "No ECS clusters (prefix='${PREFIX}')."
fi

# Deregister ECS task definitions with prefix
say "--- ECS task definitions ---"
TASK_DEFS=$(aws ecs list-task-definitions --profile "$PROFILE" --region "$REGION" --query 'taskDefinitionArns' --output text 2>/dev/null)
for td in $TASK_DEFS; do
  name="${td##*/}"
  fam="${name%%:*}"
  if [[ -z "$PREFIX" || "$fam" == *"$PREFIX"* ]]; then
    say "Deregister task def $td"
    aws ecs deregister-task-definition --task-definition "$td" --profile "$PROFILE" --region "$REGION" >/dev/null 2>&1 || true
  fi
done

########################################
# 2) Load Balancers, listeners, target groups
########################################
say "--- Load Balancers ---"
LB_ARNS=$(aws elbv2 describe-load-balancers --profile "$PROFILE" --region "$REGION" \
  --query 'LoadBalancers[*].[LoadBalancerArn,LoadBalancerName]' --output text 2>/dev/null | awk -v pfx="$PREFIX" '{ if (pfx=="" || $2 ~ pfx) print $1 }')

if [[ -n "$LB_ARNS" ]]; then
  say "Found LBs: $LB_ARNS"
  read -p "Delete ALBs/NLBs (+ listeners, TGs)? [y/N] " yn
  if [[ $yn =~ ^[Yy]$ ]]; then
    # First delete listeners and target groups attached to matching LBs
    for lb in $LB_ARNS; do
      say "Deleting listeners for $lb"
      LST=$(aws elbv2 describe-listeners --load-balancer-arn "$lb" --profile "$PROFILE" --region "$REGION" \
        --query 'Listeners[*].ListenerArn' --output text 2>/dev/null)
      for lst in $LST; do
        aws elbv2 delete-listener --listener-arn "$lst" --profile "$PROFILE" --region "$REGION" >/dev/null 2>&1 || true
      done
      say "Deleting LB $lb"
      aws elbv2 delete-load-balancer --load-balancer-arn "$lb" --profile "$PROFILE" --region "$REGION" >/dev/null 2>&1 || true
    done

    # Target groups (filtered by name prefix)
    say "Deleting target groups by prefix"
    TGS=$(aws elbv2 describe-target-groups --profile "$PROFILE" --region "$REGION" \
      --query 'TargetGroups[*].[TargetGroupArn,TargetGroupName]' --output text 2>/dev/null | awk -v pfx="$PREFIX" '{ if (pfx=="" || $2 ~ pfx) print $1 }')
    for tg in $TGS; do
      aws elbv2 delete-target-group --target-group-arn "$tg" --profile "$PROFILE" --region "$REGION" >/dev/null 2>&1 || true
    done
  fi
else
  say "No load balancers (prefix='${PREFIX}')."
fi

########################################
# 3) RDS (instances + clusters) — skip final snapshot
########################################
say "--- RDS Instances ---"
DBINSTANCES=$(aws rds describe-db-instances --profile "$PROFILE" --region "$REGION" \
  --query 'DBInstances[*].[DBInstanceIdentifier,DBName,DBInstanceArn]' --output text 2>/dev/null | awk -v pfx="$PREFIX" '{ if (pfx=="" || $1 ~ pfx) print $1 }')
if [[ -n "$DBINSTANCES" ]]; then
  say "Found instances: $DBINSTANCES"
  read -p "Delete RDS instances (skip final snapshot)? [y/N] " yn
  if [[ $yn =~ ^[Yy]$ ]]; then
    for id in $DBINSTANCES; do
      say "Deleting RDS instance $id"
      aws rds delete-db-instance --db-instance-identifier "$id" --skip-final-snapshot --profile "$PROFILE" --region "$REGION" >/dev/null 2>&1 || true
    done
  fi
else
  say "No RDS instances (prefix='${PREFIX}')."
fi

say "--- RDS Clusters ---"
DBCLUSTERS=$(aws rds describe-db-clusters --profile "$PROFILE" --region "$REGION" \
  --query 'DBClusters[*].[DBClusterIdentifier,DBClusterArn]' --output text 2>/dev/null | awk -v pfx="$PREFIX" '{ if (pfx=="" || $1 ~ pfx) print $1 }')
if [[ -n "$DBCLUSTERS" ]]; then
  say "Found clusters: $DBCLUSTERS"
  read -p "Delete RDS clusters (skip final snapshot)? [y/N] " yn
  if [[ $yn =~ ^[Yy]$ ]]; then
    for id in $DBCLUSTERS; do
      say "Deleting RDS cluster $id"
      aws rds delete-db-cluster --db-cluster-identifier "$id" --skip-final-snapshot --profile "$PROFILE" --region "$REGION" >/dev/null 2>&1 || true
    done
  fi
else
  say "No RDS clusters (prefix='${PREFIX}')."
fi

########################################
# 4) NAT Gateways & Elastic IPs
########################################
say "--- NAT Gateways ---"
NAT_IDS=$(aws ec2 describe-nat-gateways --profile "$PROFILE" --region "$REGION" \
  --query 'NatGateways[?State==`available`].[NatGatewayId,Tags]' --output text 2>/dev/null | awk -v pfx="$PREFIX" '{ if (pfx=="" || $0 ~ pfx) print $1 }')
if [[ -n "$NAT_IDS" ]]; then
  say "Found NATs: $NAT_IDS"
  read -p "Delete NAT Gateways? [y/N] " yn
  if [[ $yn =~ ^[Yy]$ ]]; then
    for id in $NAT_IDS; do
      say "Deleting NAT $id"
      aws ec2 delete-nat-gateway --nat-gateway-id "$id" --profile "$PROFILE" --region "$REGION" >/dev/null 2>&1 || true
    done
  fi
else
  say "No NAT Gateways (prefix='${PREFIX}')."
fi

say "--- Elastic IPs ---"
EIP_ALLOC=$(aws ec2 describe-addresses --profile "$PROFILE" --region "$REGION" \
  --query 'Addresses[*].[AllocationId,PublicIp,Tags]' --output text 2>/dev/null | awk -v pfx="$PREFIX" '{ if (pfx=="" || $0 ~ pfx) print $1 }')
if [[ -n "$EIP_ALLOC" ]]; then
  say "Found EIPs: $EIP_ALLOC"
  read -p "Release Elastic IPs? [y/N] " yn
  if [[ $yn =~ ^[Yy]$ ]]; then
    for id in $EIP_ALLOC; do
      say "Releasing EIP $id"
      aws ec2 release-address --allocation-id "$id" --profile "$PROFILE" --region "$REGION" >/dev/null 2>&1 || true
    done
  fi
else
  say "No Elastic IPs (prefix='${PREFIX}')."
fi

########################################
# 5) S3 Buckets (force delete) by prefix
########################################
say "--- S3 Buckets ---"
BUCKETS=$(aws s3api list-buckets --profile "$PROFILE" --query 'Buckets[*].Name' --output text 2>/dev/null)
MATCHED_BUCKETS=""
for b in $BUCKETS; do
  if [[ -z "$PREFIX" || "$b" == *"$PREFIX"* ]]; then
    MATCHED_BUCKETS="$MATCHED_BUCKETS $b"
  fi
done

if [[ -n "${MATCHED_BUCKETS// }" ]]; then
  say "Buckets: $MATCHED_BUCKETS"
  read -p "Empty and delete these S3 buckets? [y/N] " yn
  if [[ $yn =~ ^[Yy]$ ]]; then
    for b in $MATCHED_BUCKETS; do
      delete_s3_bucket "$b"
    done
  fi
else
  say "No S3 buckets (prefix='${PREFIX}')."
fi

########################################
# 6) CloudWatch log groups (ecs/ui/api names)
########################################
say "--- CloudWatch Logs (/ecs/* and prefix names) ---"
LGROUPS=$(aws logs describe-log-groups --profile "$PROFILE" --region "$REGION" \
  --query 'logGroups[*].logGroupName' --output text 2>/dev/null)
for lg in $LGROUPS; do
  if [[ -z "$PREFIX" || "$lg" == *"$PREFIX"* || "$lg" == *"/ecs/"* ]]; then
    say "Deleting log group $lg"
    aws logs delete-log-group --log-group-name "$lg" --profile "$PROFILE" --region "$REGION" >/dev/null 2>&1 || true
  fi
done

########################################
# 7) Security Groups by prefix (detached only)
########################################
say "--- Security Groups ---"
SGS=$(aws ec2 describe-security-groups --profile "$PROFILE" --region "$REGION" \
  --query 'SecurityGroups[*].[GroupId,GroupName]' --output text 2>/dev/null)
while read -r sg sgname; do
  [[ -z "$sg" ]] && continue
  if [[ -z "$PREFIX" || "$sgname" == *"$PREFIX"* ]]; then
    say "Attempting delete SG $sg ($sgname)"
    aws ec2 delete-security-group --group-id "$sg" --profile "$PROFILE" --region "$REGION" >/dev/null 2>&1 || true
  fi
done <<< "$SGS"

########################################
# 8) IAM Roles created by this project (task/execution roles)
########################################
say "--- IAM Roles ---"
IAM_ROLES=$(aws iam list-roles --profile "$PROFILE" --query 'Roles[*].RoleName' --output text 2>/dev/null)
for r in $IAM_ROLES; do
  if [[ -z "$PREFIX" || "$r" == *"$PREFIX"* ]]; then
    say "Cleaning role $r"
    # Detach managed policies
    ARNS=$(aws iam list-attached-role-policies --role-name "$r" --profile "$PROFILE" --query 'AttachedPolicies[*].PolicyArn' --output text 2>/dev/null)
    for p in $ARNS; do
      aws iam detach-role-policy --role-name "$r" --policy-arn "$p" --profile "$PROFILE" >/dev/null 2>&1 || true
    done
    # Delete inline
    INLINES=$(aws iam list-role-policies --role-name "$r" --profile "$PROFILE" --query 'PolicyNames' --output text 2>/dev/null)
    for pn in $INLINES; do
      aws iam delete-role-policy --role-name "$r" --policy-name "$pn" --profile "$PROFILE" >/dev/null 2>&1 || true
    done
    # Delete role
    aws iam delete-role --role-name "$r" --profile "$PROFILE" >/dev/null 2>&1 || true
  fi
done

say "==== Done. Some deletes may take a few minutes to fully complete in AWS."
