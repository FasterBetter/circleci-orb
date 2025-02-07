#!/bin/bash

set -eo pipefail

SetupEnv() {
  D_REGION=$(eval echo "${D_REGION}")
  D_AMI_NAME_PREFIX=$(eval echo "${D_AMI_NAME_PREFIX}")
  D_BUILD_ACCOUNT_SLUG=$(eval echo "${D_BUILD_ACCOUNT_SLUG}")

  echo "D_REGION=$D_REGION"
  echo "D_AMI_NAME_PREFIX=$D_AMI_NAME_PREFIX"
  echo "D_BUILD_ACCOUNT_SLUG=$D_BUILD_ACCOUNT_SLUG"

  export D_REGION D_AMI_NAME_PREFIX D_BUILD_ACCOUNT_SLUG
  export AWS_REGION=$D_REGION
}

IdentifyDependents() {
  local PREFIX
  PREFIX=$(aws ssm get-parameter --name "/omat/account_registry/${D_BUILD_ACCOUNT_SLUG}" --output text --query Parameter.Value | jq -r '.prefix')
  DEPENDENTS=$(aws ssm get-parameters-by-path --path "${PREFIX}/config/image_factories/${D_AMI_NAME_PREFIX}/dependents" --recursive --query 'Parameters[*].Value' | jq 'map(fromjson)')
  echo "Identified dependent image builds:"
  echo "$DEPENDENTS" | jq 'map({project_slug, branch, deploy_account})'
}

BuildCommands() {
  local RAW_API_CALLS
  RAW_API_CALLS=$(echo "$DEPENDENTS" |  jq -r 'map({url: "https://circleci.com/api/v2/project/\(.project_slug)/pipeline", data: ({branch: .branch, parameters: {in_build_account_slug: .build_account, in_deploy_account_slug: (.deploy_account // "")}} | tojson | @sh)}) | map("curl -XPOST --data \(.data) -H \"Content-Type: application/json\" -H \("Circle-Token: \($ENV.CIRCLE_TOKEN)" | @sh) \(.url)") | join("\n")')
  # This read will encounter EOF (that's the point), and we want to ignore that "error".
  set +e
  IFS=$'\n' read -r -a API_CALLS -d "" <<< "$RAW_API_CALLS"
  set -e
}

ExecuteCommands() {
  SUCCESS="true"
  for api_call in "${API_CALLS[@]}"; do
    echo "Executing command"
    echo "$api_call"
    API_RESPONSE=$(eval "$api_call")
    echo "$API_RESPONSE"
    API_ID=$(echo "$API_RESPONSE" | jq -r '.id')
    if [ -z "$API_ID" ]; then
      echo "Failed to trigger dependent build!"
      SUCCESS=
    fi
    echo ""
  done

  if [ -z "$SUCCESS" ]; then
    echo "At least one dependent build failed to trigger, failing step."
    exit 1
  fi
}

SetupEnv
IdentifyDependents
BuildCommands
ExecuteCommands
