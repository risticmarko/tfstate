#Log into Azure
#az login
#az account set --subscription "xxxxxx"
# Setup Variables.
$randomInt = Get-Random -Maximum 9999
#$randomInt = 4140 #you can reuse same code if you know randomInt

$subscriptionId=$(az account show --query id -o tsv)
$resourceGroupName = "rg-tf-core"
$storageNameDEV = "sttfstatedev$randomInt"
$storageNameUAT = "sttfstateuat$randomInt"
$storageNamePRD = "sttfstateprd$randomInt"
$kvName = "kv-tfstate-backend$randomInt"
$appName="sp-tfstate-github$randomInt"
$region = "eastus"
$keyName = "key-tfstate-cmk"
$MyIdentityDEV = "umi-dev-tfcore$randomInt"
$MyIdentityUAT = "umi-uat-tfcore$randomInt"
$MyIdentityPRD = "umi-prd-tfcore$randomInt"

# Create a resource resourceGroupName
az group create --name "$resourceGroupName" --location "$region"

# Create a Key Vault
az keyvault create `
    --name "$kvName" `
    --resource-group "$resourceGroupName" `
    --location "$region" `
    --enable-rbac-authorization `
    --enable-purge-protection true `
    --retention-days 90 

#set kv Resource ID
$kvResourceId = "/subscriptions/$subscriptionId/resourceGroups/$resourceGroupName/providers/Microsoft.KeyVault/vaults/$kvName"

# Authorize the operation to create a few secrets/keys - Signed in User (Key Vault Secrets Officer)
az ad signed-in-user show --query id -o tsv | foreach-object {
    az role assignment create `
        --role "Key Vault Secrets Officer" `
        --assignee "$_" `
        --scope $kvResourceId
    az role assignment create `
        --role "Key Vault Crypto Service Encryption User" `
        --assignee "$_" `
        --scope $kvResourceId
    az role assignment create `
        --role "Key Vault Crypto Officer" `
        --assignee "$_" `
        --scope $kvResourceId
    }

#set var for exp date 1 year from today
$ExpDate = (Get-Date).AddYears(1).ToString("yyyy-MM-dTH:mZ")

# create kv key for storage cmk
az keyvault key create --name $keyName  --vault-name $kvName --kty RSA --size 2048 --expires $ExpDate

# set json policy for key rotation
$jsonpolicy = '{
    "lifetimeActions": [
      {
        "trigger": {
          "timeAfterCreate": null,
          "timeBeforeExpiry" : "P10D"
        },
        "action": {
          "type": "Rotate"
        }
      },
      {
        "trigger": {
          "timeBeforeExpiry" : "P30D"
        },
        "action": {
          "type": "Notify"
        }
      }
    ],
    "attributes": {
      "expiryTime": "P1Y"
    }
  }'

# update kv with rotation policy
az keyvault key rotation-policy update -n $keyName --vault-name $kvName --value $jsonpolicy

# create user managed identity to set to storage account
az identity create   `
    --name $MyIdentityDEV  `
    --resource-group $resourceGroupName  `
    --location "$region"
az identity create   `
    --name $MyIdentityUAT  `
    --resource-group $resourceGroupName  `
    --location "$region"
az identity create   `
    --name $MyIdentityPRD  `
    --resource-group $resourceGroupName  `
    --location "$region"

# get identityResourceId
$identityResourceIdDEV=$(az identity show --name $MyIdentityDEV `
    --resource-group $resourceGroupName `
    --query id `
    --output tsv)
$identityResourceIdUAT=$(az identity show --name $MyIdentityUAT `
    --resource-group $resourceGroupName `
    --query id `
    --output tsv)
$identityResourceIdPRD=$(az identity show --name $MyIdentityPRD `
    --resource-group $resourceGroupName `
    --query id `
    --output tsv)

# get principal id
$principalIdDEV=$(az identity show --name $MyIdentityDEV `
    --resource-group $resourceGroupName `
    --query principalId `
    --output tsv)
$principalIdUAT=$(az identity show --name $MyIdentityUAT `
    --resource-group $resourceGroupName `
    --query principalId `
    --output tsv)
$principalIdPRD=$(az identity show --name $MyIdentityPRD `
    --resource-group $resourceGroupName `
    --query principalId `
    --output tsv)

# set rbac in kv for managed id
az role assignment create `
    --role "Key Vault Crypto Service Encryption User" `
    --assignee $principalIdDEV  `
    --scope $kvResourceId
az role assignment create `
    --role "Key Vault Crypto Service Encryption User" `
    --assignee $principalIdUAT  `
    --scope $kvResourceId
az role assignment create `
    --role "Key Vault Crypto Service Encryption User" `
    --assignee $principalIdPRD  `
    --scope $kvResourceId

#set kv uri
$vaultUri = "https://$kvName.vault.azure.net/"

# Create an azure storage account - Terraform Backend Storage Account
az storage account create `
    --name "$storageNameDEV" `
    --location "$region" `
    --resource-group "$resourceGroupName" `
    --sku "Standard_GRS" `
    --kind "StorageV2" `
    --https-only true `
    --min-tls-version "TLS1_2" `
    --allow-blob-public-access false  `
    --require-infrastructure-encryption true  `
    --identity-type SystemAssigned,UserAssigned `
    --user-identity-id $identityResourceIdDEV `
    --encryption-key-vault $vaultUri `
    --encryption-key-name $keyName `
    --encryption-key-source Microsoft.Keyvault `
    --key-vault-user-identity-id $identityResourceIdDEV

az storage account create `
    --name "$storageNameUAT" `
    --location "$region" `
    --resource-group "$resourceGroupName" `
    --sku "Standard_GRS" `
    --kind "StorageV2" `
    --https-only true `
    --min-tls-version "TLS1_2" `
    --allow-blob-public-access false  `
    --require-infrastructure-encryption true  `
    --identity-type SystemAssigned,UserAssigned `
    --user-identity-id $identityResourceIdUAT `
    --encryption-key-vault $vaultUri `
    --encryption-key-name $keyName `
    --encryption-key-source Microsoft.Keyvault `
    --key-vault-user-identity-id $identityResourceIdUAT

az storage account create `
    --name "$storageNamePRD" `
    --location "$region" `
    --resource-group "$resourceGroupName" `
    --sku "Standard_GRS" `
    --kind "StorageV2" `
    --https-only true `
    --min-tls-version "TLS1_2" `
    --allow-blob-public-access false `
    --require-infrastructure-encryption true  `
    --identity-type SystemAssigned,UserAssigned `
    --user-identity-id $identityResourceIdPRD `
    --encryption-key-vault $vaultUri `
    --encryption-key-name $keyName `
    --encryption-key-source Microsoft.Keyvault `
    --key-vault-user-identity-id $identityResourceIdPRD


# Authorize the operation to create the container - Signed in User (Storage Blob Data Contributor Role)
az ad signed-in-user show --query id -o tsv | foreach-object { 
    az role assignment create `
        --role "Storage Blob Data Contributor" `
        --assignee "$_" `
        --scope "/subscriptions/$subscriptionId/resourceGroups/$resourceGroupName/providers/Microsoft.Storage/storageAccounts/$storageNameDEV"
    }
az ad signed-in-user show --query id -o tsv | foreach-object { 
        az role assignment create `
            --role "Storage Blob Data Contributor" `
            --assignee "$_" `
            --scope "/subscriptions/$subscriptionId/resourceGroups/$resourceGroupName/providers/Microsoft.Storage/storageAccounts/$storageNameUAT"
    }
az ad signed-in-user show --query id -o tsv | foreach-object { 
            az role assignment create `
                --role "Storage Blob Data Contributor" `
                --assignee "$_" `
                --scope "/subscriptions/$subscriptionId/resourceGroups/$resourceGroupName/providers/Microsoft.Storage/storageAccounts/$storageNamePRD"
    }
#Create Upload container in storage account to store terraform state files
Start-Sleep -s 30
az storage container create `
    --account-name "$storageNameDEV" `
    --name "tfstate" `
    --auth-mode login
az storage container create `
    --account-name "$storageNameUAT" `
    --name "tfstate" `
    --auth-mode login
az storage container create `
    --account-name "$storageNamePRD" `
    --name "tfstate" `
    --auth-mode login

#set soft delete, retention and verzioning
az storage account blob-service-properties update --account-name "$storageNameDEV" `
    --resource-group $resourceGroupName `
    --enable-change-feed true `
    --enable-delete-retention true `
    --enable-container-delete-retention true  `
    --enable-versioning true `
    --enable-restore-policy true `
    --restore-days 6 `
    --container-delete-retention-days 7  `
    --delete-retention-days 7
az storage account blob-service-properties update --account-name "$storageNameUAT" `
    --resource-group $resourceGroupName `
    --enable-change-feed true  `
    --enable-delete-retention true `
    --enable-container-delete-retention true  `
    --enable-versioning true `
    --enable-restore-policy true `
    --restore-days 6 `
    --container-delete-retention-days 7  `
    --delete-retention-days 7
az storage account blob-service-properties update --account-name "$storageNamePRD" `
    --resource-group $resourceGroupName `
    --enable-change-feed true `
    --enable-delete-retention true `
    --enable-container-delete-retention true  `
    --enable-versioning true `
    --enable-restore-policy true `
    --restore-days 6 `
    --container-delete-retention-days 7  `
    --delete-retention-days 7


az storage account management-policy create  `
    --account-name "$storageNameDEV"  `
    --resource-group $resourceGroupName  `
    --policy '@policyblob.json'
az storage account management-policy create  `
    --account-name "$storageNameUAT"  `
    --resource-group $resourceGroupName  `
    --policy '@policyblob.json'
az storage account management-policy create  `
    --account-name "$storageNamePRD"  `
    --resource-group $resourceGroupName  `
    --policy '@policyblob.json'


# Create Terraform Service Principal and assign RBAC Role on Key Vault 
$spnJSON = az ad sp create-for-rbac --name $appName `
    --role "Key Vault Secrets Officer" `
    --scopes /subscriptions/$subscriptionId/resourceGroups/$resourceGroupName/providers/Microsoft.KeyVault/vaults/$kvName 

# Save new Terraform Service Principal details to key vault
$spnObj = $spnJSON | ConvertFrom-Json
foreach($object_properties in $spnObj.psobject.properties) {
    If ($object_properties.Name -eq "appId") {
        $null = az keyvault secret set --vault-name $kvName --name "ARM-CLIENT-ID" --value $object_properties.Value
    }
    If ($object_properties.Name -eq "password") {
        $null = az keyvault secret set --vault-name $kvName --name "ARM-CLIENT-SECRET" --value $object_properties.Value
    }
    If ($object_properties.Name -eq "tenant") {
        $null = az keyvault secret set --vault-name $kvName --name "ARM-TENANT-ID" --value $object_properties.Value
    }
}
$null = az keyvault secret set --vault-name $kvName --name "ARM-SUBSCRIPTION-ID" --value $subscriptionId

# Assign additional RBAC role to Terraform Service Principal Subscription as Contributor and access to backend storage
az ad sp list --display-name $appName --query [].appId -o tsv | ForEach-Object {
    az role assignment create --assignee "$_" `
        --role "Owner" `
        --subscription $subscriptionId `
        --scope "/subscriptions/$subscriptionId" 
    az role assignment create --assignee "$_" `
        --role "Storage Blob Data Contributor" `
        --scope "/subscriptions/$subscriptionId/resourceGroups/$resourceGroupName/providers/Microsoft.Storage/storageAccounts/$storageNameDEV" 
    az role assignment create --assignee "$_" `
        --role "Storage Blob Data Contributor" `
        --scope "/subscriptions/$subscriptionId/resourceGroups/$resourceGroupName/providers/Microsoft.Storage/storageAccounts/$storageNameUAT" 
    az role assignment create --assignee "$_" `
        --role "Storage Blob Data Contributor" `
        --scope "/subscriptions/$subscriptionId/resourceGroups/$resourceGroupName/providers/Microsoft.Storage/storageAccounts/$storageNamePRD" `
}

#lock rg delete
az group lock create --lock-type CanNotDelete `
    --name "DoNotDelete" `
    --resource-group $resourceGroupName `
    --notes "Protect tf state rg"
