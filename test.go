package test

import (
    "testing"

    "github.com/gruntwork-io/terratest/modules/terraform"
    "github.com/stretchr/testify/assert"
)

func TestAzureStorageBlob(t *testing.T) {
    // Specify the path to your Terraform code
    terraformOptions := &terraform.Options{
        TerraformDir: "../path/to/your/terraform/code",
    }

    // Run `terraform init` and `terraform apply` to deploy the resources
    defer terraform.Destroy(t, terraformOptions)
    terraform.InitAndApply(t, terraformOptions)

    // Get the outputs from Terraform
    storageAccountName := terraform.Output(t, terraformOptions, "storage_account_name")
    storageContainerName := terraform.Output(t, terraformOptions, "storage_container_name")
    blobName := terraform.Output(t, terraformOptions, "blob_name")

    // Add your assertions here to test the deployed resources
    // Example assertions:
    assert.NotNil(t, storageAccountName)
    assert.NotNil(t, storageContainerName)
    assert.NotNil(t, blobName)
}

func TestMain(m *testing.M) {
    // Call the tests
    code := m.Run()

    // Exit with status code
    os.Exit(code)
}
