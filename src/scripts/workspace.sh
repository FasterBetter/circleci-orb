readonly workspace="${TF_WORKSPACE:-$workspace_parameter}"
export workspace
unset TF_WORKSPACE

if [[ $workspace_parameter != "" ]]; then
  echo "[INFO] Provisioning workspace: $workspace"
  # $module_path is defined by caller.
  # shellcheck disable=SC2154
  ~/terraform/terraform -chdir="$module_path" workspace select -no-color "$workspace" || ~/terraform/terraform -chdir="$module_path" workspace new -no-color "$workspace"
else
  echo "[INFO] Using default workspace"
fi
