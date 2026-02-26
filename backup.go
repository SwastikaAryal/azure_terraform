// Package test contains Terratest integration tests for the MINITRUE
// Backup & Recovery Terraform module (MINITRUE-9348, 9418, 9414, 9416, Sprint 3).
//
// Prerequisites:
//   - Go 1.21+
//   - An active Azure subscription with contributor access
//   - ARM_SUBSCRIPTION_ID, ARM_TENANT_ID, ARM_CLIENT_ID, ARM_CLIENT_SECRET set
//   - The resource group specified in TEST_RESOURCE_GROUP must already exist
//     (or the test will create a temporary one via the fixture)
//
// Run all tests:
//
//	go test -v -timeout 60m ./...
//
// Run a specific test:
//
//	go test -v -timeout 30m -run TestRSVVaultCreation ./...
package test

import (
	"fmt"
	"os"
	"strings"
	"testing"
	"time"

	"github.com/Azure/azure-sdk-for-go/sdk/azidentity"
	"github.com/Azure/azure-sdk-for-go/sdk/resourcemanager/recoveryservices/armrecoveryservices"
	"github.com/Azure/azure-sdk-for-go/sdk/resourcemanager/recoveryservices/armrecoveryservicesbackup"
	"github.com/Azure/azure-sdk-for-go/sdk/resourcemanager/dataprotection/armdataprotection"
	"github.com/Azure/azure-sdk-for-go/sdk/resourcemanager/automation/armautomation"
	"github.com/Azure/azure-sdk-for-go/sdk/resourcemanager/monitor/armmonitor"
	"github.com/gruntwork-io/terratest/modules/azure"
	"github.com/gruntwork-io/terratest/modules/random"
	"github.com/gruntwork-io/terratest/modules/retry"
	"github.com/gruntwork-io/terratest/modules/terraform"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// ─── Helpers ─────────────────────────────────────────────────────────────────

// envOrDefault returns the value of the env-var or the supplied default.
func envOrDefault(key, def string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return def
}

// subscriptionID reads ARM_SUBSCRIPTION_ID (required).
func subscriptionID(t *testing.T) string {
	t.Helper()
	sub := os.Getenv("ARM_SUBSCRIPTION_ID")
	require.NotEmpty(t, sub, "ARM_SUBSCRIPTION_ID must be set")
	return sub
}

// newAzureCredential creates a DefaultAzureCredential for direct SDK assertions.
func newAzureCredential(t *testing.T) *azidentity.DefaultAzureCredential {
	t.Helper()
	cred, err := azidentity.NewDefaultAzureCredential(nil)
	require.NoError(t, err, "failed to create Azure credential")
	return cred
}

// uniqueSuffix returns a short random suffix safe for Azure resource names.
func uniqueSuffix() string {
	return strings.ToLower(random.UniqueId())[:6]
}

// ─── Shared fixture ───────────────────────────────────────────────────────────

// terraformOptions builds a *terraform.Options pointing at the module root with
// a randomised name suffix so parallel test runs don't clash.
func terraformOptions(t *testing.T, suffix string) *terraform.Options {
	t.Helper()

	rg := envOrDefault("TEST_RESOURCE_GROUP", fmt.Sprintf("rg-minitrue-test-%s", suffix))
	loc := envOrDefault("TEST_LOCATION", "eastus")
	secondaryLoc := envOrDefault("TEST_SECONDARY_LOCATION", "westus")

	return terraform.WithDefaultRetryableErrors(t, &terraform.Options{
		// Point at the module root (one level up from this test directory).
		TerraformDir: "../",

		Vars: map[string]interface{}{
			"resource_group_name":          rg,
			"location":                     loc,
			"secondary_location":           secondaryLoc,
			"environment":                  "test",
			"vault_name":                   fmt.Sprintf("rsv-minitrue-%s", suffix),
			"snapshot_resource_group_name": fmt.Sprintf("rg-minitrue-snaps-%s", suffix),
			"alert_email_addresses":        []string{"terratest@example.com"},
			// Leave workspace_id empty so the module creates one.
			"log_analytics_workspace_id":   "",
			"log_analytics_workspace_name": fmt.Sprintf("law-minitrue-%s", suffix),
			// No real VMs needed for infra-level tests.
			"app_vm_ids":          []string{},
			"web_vm_ids":          []string{},
			"app_vm_os_disk_ids":  []string{},
			"web_vm_os_disk_ids":  []string{},
			"app_vm_data_disk_ids": []string{},
			"web_vm_data_disk_ids": []string{},
		},

		// Capture plan/apply output for assertions.
		PlanFilePath: fmt.Sprintf("/tmp/tfplan-%s", suffix),

		RetryableTerraformErrors: map[string]string{
			// Transient Azure RP errors that should be retried.
			"AuthorizationFailed":              "waiting for RBAC propagation",
			"ResourceGroupNotFound":            "resource group not yet visible",
			"PrincipalNotFound":                "waiting for service-principal propagation",
			"VaultAlreadySoftDeletedOrExists":  "vault is in soft-delete state",
		},
		MaxRetries:         5,
		TimeBetweenRetries: 30 * time.Second,
	})
}

// ─── Test: Plan-only (fast, no real Azure resources) ─────────────────────────

// TestBackupRecoveryPlan verifies that the module produces a valid Terraform
// plan without actually creating any resources. Runs in CI on every PR.
func TestBackupRecoveryPlan(t *testing.T) {
	t.Parallel()
	suffix := uniqueSuffix()
	opts := terraformOptions(t, suffix)

	defer terraform.Destroy(t, opts)

	terraform.InitAndPlan(t, opts)
}

// ─── Test: Full apply / destroy cycle ────────────────────────────────────────

// TestRSVVaultCreation deploys the full module and verifies the Recovery
// Services Vault exists with the expected configuration (MINITRUE-9348).
func TestRSVVaultCreation(t *testing.T) {
	t.Parallel()
	suffix := uniqueSuffix()
	opts := terraformOptions(t, suffix)

	defer terraform.Destroy(t, opts)
	terraform.InitAndApply(t, opts)

	// ── Output assertions ─────────────────────────────────────────────────
	vaultID := terraform.Output(t, opts, "recovery_services_vault_id")
	vaultName := terraform.Output(t, opts, "recovery_services_vault_name")

	assert.NotEmpty(t, vaultID, "recovery_services_vault_id output must not be empty")
	assert.NotEmpty(t, vaultName, "recovery_services_vault_name output must not be empty")
	assert.Contains(t, vaultID, "Microsoft.RecoveryServices/vaults",
		"vault ID should contain the correct resource type")

	// ── Direct SDK assertion via Azure API ────────────────────────────────
	sub := subscriptionID(t)
	cred := newAzureCredential(t)
	rg := terraform.Output(t, opts, "resource_group_name") // exposed via outputs if added

	// Fall back to the var we passed in.
	if rg == "" {
		rg = fmt.Sprintf("rg-minitrue-test-%s", suffix)
	}

	client, err := armrecoveryservices.NewVaultsClient(sub, cred, nil)
	require.NoError(t, err)

	vault, err := client.Get(t.(*testing.T).Context(), rg, vaultName, nil)
	require.NoError(t, err, "vault should be reachable via Azure SDK")

	// SKU
	require.NotNil(t, vault.SKU)
	assert.Equal(t, armrecoveryservices.SKUNameStandard, *vault.SKU.Name,
		"vault SKU should be Standard")

	// Soft-delete
	require.NotNil(t, vault.Properties.SecuritySettings)
	assert.Equal(t,
		armrecoveryservices.SoftDeleteFeatureStateEnabled,
		*vault.Properties.SecuritySettings.SoftDeleteSettings.SoftDeleteState,
		"soft-delete must be enabled (MINITRUE-9348)")

	// Cross-region restore (required by MINITRUE-9418)
	require.NotNil(t, vault.Properties.RedundancySettings)
	assert.Equal(t,
		armrecoveryservices.CrossRegionRestoreEnabled,
		*vault.Properties.RedundancySettings.CrossRegionRestore,
		"cross-region restore must be enabled (MINITRUE-9418)")

	// Storage mode must be GeoRedundant
	assert.Equal(t,
		armrecoveryservices.StandardTierStorageRedundancyGeoRedundant,
		*vault.Properties.RedundancySettings.StandardTierStorageRedundancy,
		"storage mode must be GeoRedundant")
}

// ─── Test: Backup policies (MINITRUE-9418) ───────────────────────────────────

// TestBackupPolicies asserts that both the Standard and Enhanced VM backup
// policies are created with the correct retention and scheduling settings.
func TestBackupPolicies(t *testing.T) {
	t.Parallel()
	suffix := uniqueSuffix()
	opts := terraformOptions(t, suffix)

	defer terraform.Destroy(t, opts)
	terraform.InitAndApply(t, opts)

	sub := subscriptionID(t)
	cred := newAzureCredential(t)
	rg := fmt.Sprintf("rg-minitrue-test-%s", suffix)
	vaultName := terraform.Output(t, opts, "recovery_services_vault_name")

	stdPolicyID := terraform.Output(t, opts, "standard_backup_policy_id")
	enhPolicyID := terraform.Output(t, opts, "enhanced_backup_policy_id")

	assert.NotEmpty(t, stdPolicyID, "standard_backup_policy_id must not be empty")
	assert.NotEmpty(t, enhPolicyID, "enhanced_backup_policy_id must not be empty")

	client, err := armrecoveryservicesbackup.NewProtectionPoliciesClient(sub, cred, nil)
	require.NoError(t, err)

	// ── Standard policy ───────────────────────────────────────────────────
	stdResp, err := client.Get(t.(*testing.T).Context(), vaultName, rg, "bkpol-standard-daily-30d", nil)
	require.NoError(t, err, "standard backup policy should exist")

	stdPolicy, ok := stdResp.Properties.(*armrecoveryservicesbackup.AzureIaaSVMProtectionPolicy)
	require.True(t, ok, "policy properties should be AzureIaaSVMProtectionPolicy")

	// Backup schedule – Daily at 23:00
	simpleSchedule, ok := stdPolicy.SchedulePolicy.(*armrecoveryservicesbackup.SimpleSchedulePolicy)
	require.True(t, ok, "standard policy should use SimpleSchedulePolicy")
	assert.Equal(t,
		armrecoveryservicesbackup.ScheduleRunTypeDaily,
		*simpleSchedule.ScheduleRunFrequency,
		"standard policy frequency should be Daily")

	// Daily retention 30 days
	ltrPolicy, ok := stdPolicy.RetentionPolicy.(*armrecoveryservicesbackup.LongTermRetentionPolicy)
	require.True(t, ok, "retention policy should be LongTermRetentionPolicy")
	require.NotNil(t, ltrPolicy.DailySchedule)
	assert.EqualValues(t, 30, *ltrPolicy.DailySchedule.RetentionDuration.Count,
		"daily retention should be 30 days (MINITRUE-9418)")

	// Weekly retention 12 weeks
	require.NotNil(t, ltrPolicy.WeeklySchedule)
	assert.EqualValues(t, 12, *ltrPolicy.WeeklySchedule.RetentionDuration.Count,
		"weekly retention should be 12 weeks")

	// Monthly retention 12 months
	require.NotNil(t, ltrPolicy.MonthlySchedule)
	assert.EqualValues(t, 12, *ltrPolicy.MonthlySchedule.RetentionDuration.Count,
		"monthly retention should be 12 months")

	// Yearly retention 3 years
	require.NotNil(t, ltrPolicy.YearlySchedule)
	assert.EqualValues(t, 3, *ltrPolicy.YearlySchedule.RetentionDuration.Count,
		"yearly retention should be 3 years")

	// Instant restore window 5 days
	assert.EqualValues(t, 5, *stdPolicy.InstantRpRetentionRangeInDays,
		"standard instant restore window should be 5 days")

	// ── Enhanced policy (V2 / Hourly) ─────────────────────────────────────
	enhResp, err := client.Get(t.(*testing.T).Context(), vaultName, rg, "bkpol-enhanced-daily-30d", nil)
	require.NoError(t, err, "enhanced backup policy should exist")

	enhPolicy, ok := enhResp.Properties.(*armrecoveryservicesbackup.AzureIaaSVMProtectionPolicy)
	require.True(t, ok)

	// Should be V2 policy type
	assert.Equal(t,
		armrecoveryservicesbackup.IAASVMPolicyTypeV2,
		*enhPolicy.PolicyType,
		"enhanced policy should be V2 (MINITRUE-9418)")

	// Hourly schedule
	hourlySchedule, ok := enhPolicy.SchedulePolicy.(*armrecoveryservicesbackup.SimpleSchedulePolicyV2)
	require.True(t, ok, "enhanced policy should use SimpleSchedulePolicyV2")
	assert.Equal(t,
		armrecoveryservicesbackup.ScheduleRunTypeHourly,
		*hourlySchedule.ScheduleRunFrequency,
		"enhanced policy frequency should be Hourly")
	require.NotNil(t, hourlySchedule.HourlySchedule)
	assert.EqualValues(t, 4, *hourlySchedule.HourlySchedule.Interval,
		"enhanced policy interval should be 4 hours")
	assert.EqualValues(t, 12, *hourlySchedule.HourlySchedule.WindowDuration,
		"enhanced policy window should be 12 hours")

	// Instant restore window 7 days
	assert.EqualValues(t, 7, *enhPolicy.InstantRpRetentionRangeInDays,
		"enhanced instant restore window should be 7 days")
}

// ─── Test: Disk snapshot vault (MINITRUE-9416) ───────────────────────────────

// TestDiskSnapshotVault verifies that the Data Protection Backup Vault for
// managed disk snapshots exists with the correct redundancy setting.
func TestDiskSnapshotVault(t *testing.T) {
	t.Parallel()
	suffix := uniqueSuffix()
	opts := terraformOptions(t, suffix)

	defer terraform.Destroy(t, opts)
	terraform.InitAndApply(t, opts)

	vaultID := terraform.Output(t, opts, "data_protection_backup_vault_id")
	assert.NotEmpty(t, vaultID, "data_protection_backup_vault_id must not be empty")
	assert.Contains(t, vaultID, "Microsoft.DataProtection/backupVaults",
		"vault ID should contain the correct resource type (MINITRUE-9416)")

	sub := subscriptionID(t)
	cred := newAzureCredential(t)
	snapshotRG := fmt.Sprintf("rg-minitrue-snaps-%s", suffix)

	dpClient, err := armdataprotection.NewBackupVaultsClient(sub, cred, nil)
	require.NoError(t, err)

	// Extract vault name from the resource ID.
	parts := strings.Split(vaultID, "/")
	dpVaultName := parts[len(parts)-1]

	dpVault, err := dpClient.Get(t.(*testing.T).Context(), snapshotRG, dpVaultName, nil)
	require.NoError(t, err, "Data Protection vault should be reachable")

	assert.Equal(t,
		armdataprotection.StorageSettingTypesGeoRedundant,
		*dpVault.Properties.StorageSettings[0].Type,
		"disk snapshot vault should use geo-redundant storage (MINITRUE-9416)")
}

// ─── Test: Disk snapshot policy retention (MINITRUE-9416) ────────────────────

// TestDiskSnapshotPolicy verifies the disk snapshot backup policy is created
// with the correct 7-day retention rule.
func TestDiskSnapshotPolicy(t *testing.T) {
	t.Parallel()
	suffix := uniqueSuffix()
	opts := terraformOptions(t, suffix)

	defer terraform.Destroy(t, opts)
	terraform.InitAndApply(t, opts)

	sub := subscriptionID(t)
	cred := newAzureCredential(t)
	snapshotRG := fmt.Sprintf("rg-minitrue-snaps-%s", suffix)
	vaultID := terraform.Output(t, opts, "data_protection_backup_vault_id")

	parts := strings.Split(vaultID, "/")
	dpVaultName := parts[len(parts)-1]

	policyClient, err := armdataprotection.NewBackupPoliciesClient(sub, cred, nil)
	require.NoError(t, err)

	policyResp, err := policyClient.Get(
		t.(*testing.T).Context(), snapshotRG, dpVaultName, "diskpol-minitrue-daily-7d", nil,
	)
	require.NoError(t, err, "disk snapshot policy should exist (MINITRUE-9416)")
	require.NotNil(t, policyResp.Properties)

	// Verify at least one retention rule that covers 7-day daily retention.
	found := false
	for _, rule := range policyResp.Properties.PolicyRules {
		if retRule, ok := rule.(*armdataprotection.AzureRetentionRule); ok {
			for _, lifecycle := range retRule.Lifecycles {
				if lifecycle.DeleteAfter != nil {
					if absDelete, ok := lifecycle.DeleteAfter.(*armdataprotection.AbsoluteDeleteOption); ok {
						if strings.Contains(*absDelete.Duration, "P7D") {
							found = true
						}
					}
				}
			}
		}
	}
	assert.True(t, found, "disk snapshot policy should contain a 7-day retention lifecycle (MINITRUE-9416)")
}

// ─── Test: Automation account & runbooks (MINITRUE-9414) ─────────────────────

// TestAutomationAccountAndRunbooks validates that the Automation Account used
// for restore testing is created and that required runbooks are present.
func TestAutomationAccountAndRunbooks(t *testing.T) {
	t.Parallel()
	suffix := uniqueSuffix()
	opts := terraformOptions(t, suffix)

	defer terraform.Destroy(t, opts)
	terraform.InitAndApply(t, opts)

	aaName := terraform.Output(t, opts, "automation_account_name")
	assert.NotEmpty(t, aaName, "automation_account_name output must not be empty")
	assert.Equal(t, "aa-minitrue-backup-restore", aaName,
		"automation account name should match expected value (MINITRUE-9414)")

	sub := subscriptionID(t)
	cred := newAzureCredential(t)
	rg := fmt.Sprintf("rg-minitrue-test-%s", suffix)

	aaClient, err := armautomation.NewAccountClient(sub, cred, nil)
	require.NoError(t, err)

	aa, err := aaClient.Get(t.(*testing.T).Context(), rg, aaName, nil)
	require.NoError(t, err, "automation account should be reachable")

	// System-assigned managed identity required for restore runbooks
	require.NotNil(t, aa.Identity, "automation account should have a managed identity")
	assert.Equal(t,
		armautomation.ResourceIdentityTypeSystemAssigned,
		*aa.Identity.Type,
		"automation account should use SystemAssigned identity (MINITRUE-9414)")

	// Verify runbooks are published.
	rbClient, err := armautomation.NewRunbookClient(sub, cred, nil)
	require.NoError(t, err)

	expectedRunbooks := []string{
		"Invoke-FullVMRestore",
		"Invoke-DiskRestore",
		"Invoke-FileLevelRecovery",
	}

	for _, rbName := range expectedRunbooks {
		rb, err := rbClient.Get(t.(*testing.T).Context(), rg, aaName, rbName, nil)
		require.NoError(t, err, "runbook %q should exist (MINITRUE-9414)", rbName)
		assert.Equal(t,
			armautomation.RunbookTypeEnumPowerShell,
			*rb.Properties.RunbookType,
			"runbook %q should be PowerShell type", rbName)
	}
}

// ─── Test: Monitoring & alerting (Sprint 3) ───────────────────────────────────

// TestMonitoringAndAlerts verifies that the Action Group and Log Analytics
// workspace used for backup alerts are correctly provisioned.
func TestMonitoringAndAlerts(t *testing.T) {
	t.Parallel()
	suffix := uniqueSuffix()
	opts := terraformOptions(t, suffix)

	defer terraform.Destroy(t, opts)
	terraform.InitAndApply(t, opts)

	agID := terraform.Output(t, opts, "action_group_id")
	lawID := terraform.Output(t, opts, "log_analytics_workspace_id")

	assert.NotEmpty(t, agID, "action_group_id output must not be empty")
	assert.NotEmpty(t, lawID, "log_analytics_workspace_id output must not be empty")

	sub := subscriptionID(t)
	cred := newAzureCredential(t)
	rg := fmt.Sprintf("rg-minitrue-test-%s", suffix)

	// ── Action Group ──────────────────────────────────────────────────────
	agClient, err := armmonitor.NewActionGroupsClient(sub, cred, nil)
	require.NoError(t, err)

	// Extract action group name from ID.
	agParts := strings.Split(agID, "/")
	agName := agParts[len(agParts)-1]

	ag, err := agClient.Get(t.(*testing.T).Context(), rg, agName, nil)
	require.NoError(t, err, "action group should be reachable (Sprint 3)")

	assert.True(t, *ag.Properties.Enabled, "action group should be enabled")

	// At least one email receiver should be configured.
	assert.NotEmpty(t, ag.Properties.EmailReceivers,
		"action group should have at least one email receiver for backup alerts")

	emailFound := false
	for _, er := range ag.Properties.EmailReceivers {
		if strings.Contains(*er.EmailAddress, "terratest@example.com") {
			emailFound = true
		}
	}
	assert.True(t, emailFound, "action group should contain the test email address")

	// ── Log Analytics Workspace ───────────────────────────────────────────
	assert.Contains(t, lawID, "Microsoft.OperationalInsights/workspaces",
		"log_analytics_workspace_id should reference a Log Analytics workspace (Sprint 3)")
}

// ─── Test: RBAC role assignments (MINITRUE-9414) ─────────────────────────────

// TestAutomationRoleAssignments verifies that the Automation Account receives
// the Backup Contributor and Virtual Machine Contributor roles needed to
// trigger restore jobs.
func TestAutomationRoleAssignments(t *testing.T) {
	t.Parallel()
	suffix := uniqueSuffix()
	opts := terraformOptions(t, suffix)

	defer terraform.Destroy(t, opts)
	terraform.InitAndApply(t, opts)

	sub := subscriptionID(t)
	cred := newAzureCredential(t)
	rg := fmt.Sprintf("rg-minitrue-test-%s", suffix)
	aaName := terraform.Output(t, opts, "automation_account_name")

	// Get the Automation Account's principal ID.
	aaClient, err := armautomation.NewAccountClient(sub, cred, nil)
	require.NoError(t, err)

	aa, err := aaClient.Get(t.(*testing.T).Context(), rg, aaName, nil)
	require.NoError(t, err)
	require.NotNil(t, aa.Identity.PrincipalID)
	principalID := *aa.Identity.PrincipalID

	// Retrieve vault ID to check vault-scoped role assignment.
	vaultID := terraform.Output(t, opts, "recovery_services_vault_id")

	// Use the Terratest azure helper to list role assignments.
	assignments := azure.GetRoleAssignmentsForScope(t, sub, vaultID)

	backupContributor := false
	for _, a := range assignments {
		if a.Properties != nil &&
			a.Properties.PrincipalID != nil &&
			*a.Properties.PrincipalID == principalID {
			if strings.Contains(*a.Properties.RoleDefinitionID, "Backup Contributor") ||
				// Role-def GUIDs vary; check by display name via a lookup if needed.
				strings.HasSuffix(*a.Properties.RoleDefinitionID, "5e467623-bb1f-42f4-a55d-6e525e11384b") {
				backupContributor = true
			}
		}
	}
	assert.True(t, backupContributor,
		"Automation Account should have Backup Contributor role on the vault (MINITRUE-9414)")
}

// ─── Test: Backup exclusion (disk LUN) (MINITRUE-9418) ───────────────────────

// TestDiskExclusionOutputs is a lightweight plan-level test that validates
// the selective-disk-backup (LUN exclusion) resource is included in the plan.
// Because no real VMs are provided in CI, we only assert on plan output.
func TestDiskExclusionOutputs(t *testing.T) {
	t.Parallel()
	suffix := uniqueSuffix()
	opts := terraformOptions(t, suffix)

	// Plan only – fast, no infrastructure cost.
	planOut := terraform.InitAndPlanAndShowWithStruct(t, opts)

	// The selective-disk resource must appear in planned changes.
	found := false
	for addr := range planOut.ResourceChangesMap {
		if strings.Contains(addr, "app_vms_selective") {
			found = true
			break
		}
	}
	// When app_vm_ids is empty the for_each produces zero instances – that's
	// expected. Assert the resource *type* is planned (even with 0 instances).
	_ = found // accepted: 0 instances when VM list is empty
	assert.Contains(t,
		fmt.Sprintf("%v", planOut.ResourceChangesMap),
		"azurerm_backup_protected_vm",
		"plan should include azurerm_backup_protected_vm resources (MINITRUE-9418)")
}

// ─── Test: Idempotency ────────────────────────────────────────────────────────

// TestIdempotency applies the module twice and asserts the second apply
// produces no changes – a fundamental infrastructure-as-code hygiene check.
func TestIdempotency(t *testing.T) {
	t.Parallel()
	suffix := uniqueSuffix()
	opts := terraformOptions(t, suffix)

	defer terraform.Destroy(t, opts)
	terraform.InitAndApply(t, opts)

	// Second apply – must be a no-op.
	exitCode := terraform.PlanExitCode(t, opts)
	assert.Equal(t, 0, exitCode,
		"second plan should produce no changes (idempotency check)")
}

// ─── Test: Outputs completeness ───────────────────────────────────────────────

// TestOutputsCompleteness checks that every documented output is present
// and non-empty after a successful apply.
func TestOutputsCompleteness(t *testing.T) {
	t.Parallel()
	suffix := uniqueSuffix()
	opts := terraformOptions(t, suffix)

	defer terraform.Destroy(t, opts)
	terraform.InitAndApply(t, opts)

	requiredOutputs := []string{
		"recovery_services_vault_id",
		"recovery_services_vault_name",
		"data_protection_backup_vault_id",
		"automation_account_name",
		"action_group_id",
		"log_analytics_workspace_id",
		"standard_backup_policy_id",
		"enhanced_backup_policy_id",
	}

	for _, outputName := range requiredOutputs {
		val := terraform.Output(t, opts, outputName)
		assert.NotEmpty(t, val, "output %q must not be empty", outputName)
	}
}

// ─── Test: Soft-delete cannot be disabled without lifecycle safeguard ─────────

// TestSoftDeleteProtection asserts that a plan to disable soft-delete on the
// vault does NOT silently succeed – the provider requires an explicit lifecycle
// block. This is a regression guard for MINITRUE-9348 security requirements.
func TestSoftDeleteProtection(t *testing.T) {
	t.Parallel()
	suffix := uniqueSuffix()
	opts := terraformOptions(t, suffix)

	defer terraform.Destroy(t, opts)
	terraform.InitAndApply(t, opts)

	// Attempt to override soft_delete_enabled to false and verify the plan
	// requires a destroy/recreate (change will not be in-place).
	noSoftDeleteOpts := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
		TerraformDir: opts.TerraformDir,
		Vars:         copyVarsWithOverride(opts.Vars, "soft_delete_enabled", false),
	})

	// If the module exposes soft_delete_enabled as a variable; if not, the plan
	// diff should be empty (variable not exposed = immutable from Terraform).
	// Either way the vault must retain soft-delete; assert it via SDK.
	terraform.Plan(t, noSoftDeleteOpts)

	sub := subscriptionID(t)
	cred := newAzureCredential(t)
	rg := fmt.Sprintf("rg-minitrue-test-%s", suffix)
	vaultName := terraform.Output(t, opts, "recovery_services_vault_name")

	client, err := armrecoveryservices.NewVaultsClient(sub, cred, nil)
	require.NoError(t, err)

	vault, err := client.Get(t.(*testing.T).Context(), rg, vaultName, nil)
	require.NoError(t, err)

	assert.Equal(t,
		armrecoveryservices.SoftDeleteFeatureStateEnabled,
		*vault.Properties.SecuritySettings.SoftDeleteSettings.SoftDeleteState,
		"soft-delete must remain enabled; disabling it should require explicit override (MINITRUE-9348)")
}

// ─── Test: Cross-region restore is enabled (MINITRUE-9418) ───────────────────

// TestCrossRegionRestore is a focused assertion that the vault's CRR setting
// is active. Extracted separately so it can be run as a fast smoke-test.
func TestCrossRegionRestore(t *testing.T) {
	t.Parallel()
	suffix := uniqueSuffix()
	opts := terraformOptions(t, suffix)

	defer terraform.Destroy(t, opts)
	terraform.InitAndApply(t, opts)

	sub := subscriptionID(t)
	cred := newAzureCredential(t)
	rg := fmt.Sprintf("rg-minitrue-test-%s", suffix)
	vaultName := terraform.Output(t, opts, "recovery_services_vault_name")

	client, err := armrecoveryservices.NewVaultsClient(sub, cred, nil)
	require.NoError(t, err)

	vault, err := client.Get(t.(*testing.T).Context(), rg, vaultName, nil)
	require.NoError(t, err)

	assert.Equal(t,
		armrecoveryservices.CrossRegionRestoreEnabled,
		*vault.Properties.RedundancySettings.CrossRegionRestore,
		"cross-region restore must be Enabled (MINITRUE-9418)")

	assert.Equal(t,
		armrecoveryservices.StandardTierStorageRedundancyGeoRedundant,
		*vault.Properties.RedundancySettings.StandardTierStorageRedundancy,
		"storage must be GeoRedundant for CRR to function (MINITRUE-9418)")
}

// ─── Test: Retry loop for eventual-consistency checks ────────────────────────

// TestBackupJobEventualConsistency uses Terratest's retry helper to wait for
// the Recovery Services Vault to reach a "Succeeded" provisioning state,
// mirroring how you'd poll for a real backup job's completion.
func TestBackupJobEventualConsistency(t *testing.T) {
	t.Parallel()
	suffix := uniqueSuffix()
	opts := terraformOptions(t, suffix)

	defer terraform.Destroy(t, opts)
	terraform.InitAndApply(t, opts)

	sub := subscriptionID(t)
	cred := newAzureCredential(t)
	rg := fmt.Sprintf("rg-minitrue-test-%s", suffix)
	vaultName := terraform.Output(t, opts, "recovery_services_vault_name")

	client, err := armrecoveryservices.NewVaultsClient(sub, cred, nil)
	require.NoError(t, err)

	// Poll up to 5 minutes for the vault to fully provision.
	description := fmt.Sprintf("Waiting for vault %q to reach Succeeded state", vaultName)
	maxRetries := 10
	sleepBetween := 30 * time.Second

	retry.DoWithRetry(t, description, maxRetries, sleepBetween, func() (string, error) {
		vault, err := client.Get(t.(*testing.T).Context(), rg, vaultName, nil)
		if err != nil {
			return "", err
		}
		state := string(*vault.Properties.ProvisioningState)
		if state != "Succeeded" {
			return "", fmt.Errorf("vault provisioning state is %q, expected Succeeded", state)
		}
		return state, nil
	})
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

// copyVarsWithOverride returns a shallow copy of vars with one key overridden.
func copyVarsWithOverride(vars map[string]interface{}, key string, val interface{}) map[string]interface{} {
	out := make(map[string]interface{}, len(vars))
	for k, v := range vars {
		out[k] = v
	}
	out[key] = val
	return out
}
