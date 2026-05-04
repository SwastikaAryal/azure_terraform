#!/usr/bin/env bash
# ============================================================================
# tf-rebuild-state-nojq.sh  (v2 — strips CRLF for Git Bash on Windows)
# Rebuilds Terraform config + state for an Azure Resource Group when the
# state file (and possibly .tf files) have been lost.
#
# Strategy (requires Terraform >= 1.5):
#   1. Enumerate every resource in the RG via `az resource list`.
#   2. Map each Azure type to its azurerm_* Terraform type.
#   3. Emit an `import {}` block per resource into ./imports.tf.
#   4. You then run:
#        terraform plan -generate-config-out=generated.tf
#        terraform apply
#
# Usage:
#   ./tf-rebuild-state-nojq.sh <resource-group> [--subscription <id>] [--bootstrap]
#
# Requirements: az CLI (logged in), terraform >= 1.5
# ============================================================================

set -euo pipefail

RG=""
SUBSCRIPTION=""
BOOTSTRAP=false

usage() { grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 1; }
[[ $# -lt 1 ]] && usage
RG="$1"; shift

while [[ $# -gt 0 ]]; do
  case "$1" in
    --subscription) SUBSCRIPTION="$2"; shift 2 ;;
    --bootstrap)    BOOTSTRAP=true; shift ;;
    -h|--help)      usage ;;
    *) echo "Unknown arg: $1"; usage ;;
  esac
done

# ---------- pre-flight ------------------------------------------------------
command -v az        >/dev/null || { echo "az CLI not found";    exit 1; }
command -v terraform >/dev/null || { echo "terraform not found"; exit 1; }

TF_VER=$(terraform version | head -1 | awk '{print $2}' | tr -d 'v\r')
if [[ "$(printf '%s\n1.5.0\n' "$TF_VER" | sort -V | head -1)" != "1.5.0" ]]; then
  echo "Terraform $TF_VER detected. This flow needs >= 1.5 for import blocks + -generate-config-out."
  exit 1
fi

if [[ -n "$SUBSCRIPTION" ]]; then
  az account set --subscription "$SUBSCRIPTION"
fi
SUB_ID=$(az account show --query id -o tsv | tr -d '\r')
TENANT_ID=$(az account show --query tenantId -o tsv | tr -d '\r')

# ---------- bootstrap provider + init (optional) ---------------------------
if $BOOTSTRAP; then
  if [[ ! -f provider.tf ]]; then
    cat > provider.tf <<EOF
terraform {
  required_version = ">= 1.5.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.100"
    }
  }
}

provider "azurerm" {
  features {}
  subscription_id = "$SUB_ID"
  tenant_id       = "$TENANT_ID"
}
EOF
    echo "Wrote provider.tf"
  fi
  if [[ ! -d .terraform ]]; then
    terraform init -input=false
  fi
fi

[[ -d .terraform ]] || { echo "Run 'terraform init' (or pass --bootstrap)."; exit 1; }

# ---------- Azure -> Terraform type map ------------------------------------
declare -A TYPE_MAP=(
  [microsoft.resources/resourcegroups]="azurerm_resource_group"
  [microsoft.compute/virtualmachines]="azurerm_linux_virtual_machine"
  [microsoft.compute/disks]="azurerm_managed_disk"
  [microsoft.compute/availabilitysets]="azurerm_availability_set"
  [microsoft.compute/virtualmachinescalesets]="azurerm_linux_virtual_machine_scale_set"
  [microsoft.compute/snapshots]="azurerm_snapshot"
  [microsoft.compute/images]="azurerm_image"
  [microsoft.network/virtualnetworks]="azurerm_virtual_network"
  [microsoft.network/networksecuritygroups]="azurerm_network_security_group"
  [microsoft.network/networkinterfaces]="azurerm_network_interface"
  [microsoft.network/publicipaddresses]="azurerm_public_ip"
  [microsoft.network/loadbalancers]="azurerm_lb"
  [microsoft.network/applicationgateways]="azurerm_application_gateway"
  [microsoft.network/routetables]="azurerm_route_table"
  [microsoft.network/privateendpoints]="azurerm_private_endpoint"
  [microsoft.network/privatednszones]="azurerm_private_dns_zone"
  [microsoft.network/dnszones]="azurerm_dns_zone"
  [microsoft.network/firewallpolicies]="azurerm_firewall_policy"
  [microsoft.network/azurefirewalls]="azurerm_firewall"
  [microsoft.network/bastionhosts]="azurerm_bastion_host"
  [microsoft.network/virtualnetworkgateways]="azurerm_virtual_network_gateway"
  [microsoft.network/localnetworkgateways]="azurerm_local_network_gateway"
  [microsoft.storage/storageaccounts]="azurerm_storage_account"
  [microsoft.keyvault/vaults]="azurerm_key_vault"
  [microsoft.containerregistry/registries]="azurerm_container_registry"
  [microsoft.containerservice/managedclusters]="azurerm_kubernetes_cluster"
  [microsoft.web/sites]="azurerm_linux_web_app"
  [microsoft.web/serverfarms]="azurerm_service_plan"
  [microsoft.web/staticsites]="azurerm_static_site"
  [microsoft.sql/servers]="azurerm_mssql_server"
  [microsoft.sql/servers/databases]="azurerm_mssql_database"
  [microsoft.dbforpostgresql/flexibleservers]="azurerm_postgresql_flexible_server"
  [microsoft.dbformysql/flexibleservers]="azurerm_mysql_flexible_server"
  [microsoft.documentdb/databaseaccounts]="azurerm_cosmosdb_account"
  [microsoft.cache/redis]="azurerm_redis_cache"
  [microsoft.servicebus/namespaces]="azurerm_servicebus_namespace"
  [microsoft.eventhub/namespaces]="azurerm_eventhub_namespace"
  [microsoft.operationalinsights/workspaces]="azurerm_log_analytics_workspace"
  [microsoft.insights/components]="azurerm_application_insights"
  [microsoft.insights/actiongroups]="azurerm_monitor_action_group"
  [microsoft.managedidentity/userassignedidentities]="azurerm_user_assigned_identity"
  [microsoft.recoveryservices/vaults]="azurerm_recovery_services_vault"
  [microsoft.automation/automationaccounts]="azurerm_automation_account"
  [microsoft.apimanagement/service]="azurerm_api_management"
  [microsoft.signalrservice/signalr]="azurerm_signalr_service"
  [microsoft.cdn/profiles]="azurerm_cdn_profile"
  [microsoft.search/searchservices]="azurerm_search_service"
)

sanitize() {
  # also strip CR just in case it sneaks in via a name
  echo "$1" | tr -d '\r' | tr '[:upper:]' '[:lower:]' \
    | sed -E 's/[^a-z0-9_]+/_/g; s/^_+|_+$//g; s/^([0-9])/_\1/'
}

# ---------- discovery (no jq: ask az for TSV directly, strip CRLF) ---------
echo "Listing resources in resource group: $RG"
RG_ID=$(az group show --name "$RG" --query id -o tsv | tr -d '\r')

# Pull just the three fields we need, tab-separated, one resource per line.
# tr -d '\r' is essential on Git Bash for Windows; without it each line ends
# in \r which gets embedded inside the quoted "id = ..." string and breaks
# `terraform plan`.
RESOURCES_TSV=$(az resource list --resource-group "$RG" \
  --query "[].[type, name, id]" -o tsv | tr -d '\r')

COUNT=$(printf '%s\n' "$RESOURCES_TSV" | grep -c . || true)
echo "Found $COUNT child resources (plus the RG itself)."

IMPORTS_FILE="imports.tf"
SKIPPED_LOG="./skipped.log"
: > "$IMPORTS_FILE"
: > "$SKIPPED_LOG"

emit_import() {
  local tf_type="$1" tf_name="$2" az_id="$3"
  cat >> "$IMPORTS_FILE" <<EOF
import {
  to = ${tf_type}.${tf_name}
  id = "${az_id}"
}

EOF
}

# 1) Resource group itself
emit_import "azurerm_resource_group" "$(sanitize "$RG")" "$RG_ID"

# 2) Child resources — read TSV line by line
declare -A NAME_SEEN
while IFS=$'\t' read -r AZ_TYPE AZ_NAME AZ_ID; do
  # belt-and-suspenders CRLF strip on every field
  AZ_TYPE="${AZ_TYPE//$'\r'/}"
  AZ_NAME="${AZ_NAME//$'\r'/}"
  AZ_ID="${AZ_ID//$'\r'/}"

  [[ -z "${AZ_TYPE:-}" ]] && continue

  KEY=$(echo "$AZ_TYPE" | tr '[:upper:]' '[:lower:]')
  TF_TYPE="${TYPE_MAP[$KEY]:-}"

  if [[ -z "$TF_TYPE" ]]; then
    echo "$AZ_TYPE  $AZ_ID" >> "$SKIPPED_LOG"
    echo "-- skipping unmapped type: $AZ_TYPE ($AZ_NAME)"
    continue
  fi

  BASE=$(sanitize "$AZ_NAME")
  TF_NAME="$BASE"
  KEY2="${TF_TYPE}.${TF_NAME}"
  i=2
  while [[ -n "${NAME_SEEN[$KEY2]:-}" ]]; do
    TF_NAME="${BASE}_${i}"
    KEY2="${TF_TYPE}.${TF_NAME}"
    ((i++))
  done
  NAME_SEEN[$KEY2]=1

  emit_import "$TF_TYPE" "$TF_NAME" "$AZ_ID"
done <<< "$RESOURCES_TSV"

# Final safety net: scrub any stray CR from the output file itself.
sed -i 's/\r//g' "$IMPORTS_FILE" 2>/dev/null || true

WRITTEN=$(grep -c '^import {' "$IMPORTS_FILE" || true)
SKIPPED=$(wc -l < "$SKIPPED_LOG" | tr -d ' ')

cat <<EOF

==================== DONE ====================
Wrote $WRITTEN import blocks to ./$IMPORTS_FILE
Skipped (unmapped types): $SKIPPED   (see ./skipped.log)

NEXT STEPS:
  1) terraform plan -generate-config-out=generated.tf
  2) Review the plan. It must say "0 to add, 0 to change, 0 to destroy"
     and only show imports.
  3) terraform apply        # this is what writes terraform.tfstate
==============================================
EOF
