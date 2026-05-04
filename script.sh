#!/usr/bin/env bash
# ============================================================================
# tf-rebuild-state.sh
# Rebuilds Terraform config + state for an Azure Resource Group when the
# state file (and possibly .tf files) have been lost.
#
# Strategy (requires Terraform >= 1.5):
#   1. Enumerate every resource in the RG via `az resource list`.
#   2. Map each Azure type to its azurerm_* Terraform type.
#   3. Emit an `import {}` block per resource into ./imports.tf.
#   4. You then run:
#        terraform plan -generate-config-out=generated.tf
#        terraform apply        # this is what actually creates state
#
# Usage:
#   ./tf-rebuild-state.sh <resource-group> [--subscription <id>] [--bootstrap]
#
# --bootstrap  also writes a minimal provider.tf and runs `terraform init`
#              so you can run this in an empty directory.
#
# Requirements: az CLI (logged in), terraform >= 1.5, jq
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
command -v jq        >/dev/null || { echo "jq not found";        exit 1; }

TF_VER=$(terraform version -json | jq -r '.terraform_version')
if [[ "$(printf '%s\n1.5.0\n' "$TF_VER" | sort -V | head -1)" != "1.5.0" ]]; then
  echo "Terraform $TF_VER detected. This flow needs >= 1.5 for import blocks + -generate-config-out."
  exit 1
fi

if [[ -n "$SUBSCRIPTION" ]]; then
  az account set --subscription "$SUBSCRIPTION"
fi
SUB_ID=$(az account show --query id -o tsv)
TENANT_ID=$(az account show --query tenantId -o tsv)

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
  echo "$1" | tr '[:upper:]' '[:lower:]' \
    | sed -E 's/[^a-z0-9_]+/_/g; s/^_+|_+$//g; s/^([0-9])/_\1/'
}

# ---------- discovery -------------------------------------------------------
echo "Listing resources in resource group: $RG"
RG_ID=$(az group show --name "$RG" --query id -o tsv)
RESOURCES_JSON=$(az resource list --resource-group "$RG" -o json)
COUNT=$(echo "$RESOURCES_JSON" | jq 'length')
echo "Found $COUNT child resources (plus the RG itself)."

IMPORTS_FILE="imports.tf"
SKIPPED_LOG="./skipped.log"
: > "$IMPORTS_FILE"
: > "$SKIPPED_LOG"

# ---------- emit import blocks ---------------------------------------------
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

# 2) Children
declare -A NAME_SEEN
echo "$RESOURCES_JSON" | jq -c '.[]' | while read -r row; do
  AZ_TYPE=$(echo "$row" | jq -r '.type')
  AZ_NAME=$(echo "$row" | jq -r '.name')
  AZ_ID=$(echo "$row"   | jq -r '.id')

  KEY=$(echo "$AZ_TYPE" | tr '[:upper:]' '[:lower:]')
  TF_TYPE="${TYPE_MAP[$KEY]:-}"

  if [[ -z "$TF_TYPE" ]]; then
    echo "$AZ_TYPE  $AZ_ID" >> "$SKIPPED_LOG"
    echo "-- skipping unmapped type: $AZ_TYPE ($AZ_NAME)"
    continue
  fi

  BASE=$(sanitize "$AZ_NAME")
  TF_NAME="$BASE"
  # de-duplicate within the same TF type
  KEY2="${TF_TYPE}.${TF_NAME}"
  i=2
  while [[ -n "${NAME_SEEN[$KEY2]:-}" ]]; do
    TF_NAME="${BASE}_${i}"
    KEY2="${TF_TYPE}.${TF_NAME}"
    ((i++))
  done
  NAME_SEEN[$KEY2]=1

  emit_import "$TF_TYPE" "$TF_NAME" "$AZ_ID"
done

WRITTEN=$(grep -c '^import {' "$IMPORTS_FILE" || true)
SKIPPED=$(wc -l < "$SKIPPED_LOG" | tr -d ' ')

cat <<EOF

==================== DONE ====================
Wrote $WRITTEN import blocks to ./$IMPORTS_FILE
Skipped (unmapped types): $SKIPPED   (see ./skipped.log; extend TYPE_MAP and re-run if needed)

NEXT STEPS — this is what actually rebuilds your state:

  1) Generate matching Terraform config from the imports:
       terraform plan -generate-config-out=generated.tf

     If plan complains about already-defined resources or missing
     attributes, fix them in generated.tf and re-run plan.

  2) Once plan is clean and shows only the imports (no creates/deletes):
       terraform apply

     This actually writes terraform.tfstate with all the imported resources.

  3) Inspect drift and tidy generated.tf:
       terraform plan
     Re-run until it reports "No changes". Then commit your code +
     push state to remote backend so you don't lose it again.

NOTES:
  - Sub-resources like NSG rules, subnets, SQL DBs under a server, RBAC
    role assignments, key vault access policies, and diagnostic settings
    are NOT returned by 'az resource list' and need to be imported
    separately (or refactored as inline blocks of their parent).
  - Linux vs Windows: this map defaults to Linux variants for VMs and
    Web Apps. Edit imports.tf before step 1 if you have Windows ones.
==============================================
EOF
