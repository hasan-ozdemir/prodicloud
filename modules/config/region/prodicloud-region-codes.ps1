# Azure region-code helpers.

# Handles Get-ProdicloudRegionCodeMap.
function Get-ProdicloudRegionCodeMap {
    return @{
        'austriaeast' = 'ate1'
        'austriawest' = 'atw1'
        'centralindia' = 'inc1'
        'southindia' = 'ins1'
        'westindia' = 'inw1'
        'eastus' = 'use1'
        'eastus2' = 'use2'
        'centralus' = 'usc1'
        'northcentralus' = 'usn1'
        'southcentralus' = 'uss1'
        'westus' = 'usw1'
        'westus2' = 'usw2'
        'westus3' = 'usw3'
        'westcentralus' = 'usw4'
        'canadacentral' = 'cac1'
        'canadaeast' = 'cae1'
        'mexicocentral' = 'mxc1'
        'brazilsouth' = 'brs1'
        'brazilsoutheast' = 'brs2'
        'chilecentral' = 'clc1'
        'northeurope' = 'eun1'
        'westeurope' = 'euw1'
        'francecentral' = 'frc1'
        'francesouth' = 'frs1'
        'germanywestcentral' = 'gew1'
        'germanynorth' = 'gen1'
        'italynorth' = 'itn1'
        'norwayeast' = 'noe1'
        'norwaywest' = 'now1'
        'polandcentral' = 'plc1'
        'spaincentral' = 'esc1'
        'swedencentral' = 'sec1'
        'swedensouth' = 'ses1'
        'switzerlandnorth' = 'chn1'
        'switzerlandwest' = 'chw1'
        'uksouth' = 'gbs1'
        'ukwest' = 'gbw1'
        'finlandcentral' = 'fic1'
        'eastasia' = 'ase1'
        'southeastasia' = 'ass1'
        'japaneast' = 'jpe1'
        'japanwest' = 'jpw1'
        'koreacentral' = 'krc1'
        'koreasouth' = 'krs1'
        'singapore' = 'sgc1'
        'indonesiacentral' = 'idc1'
        'malaysiawest' = 'myw1'
        'newzealandnorth' = 'nzn1'
        'australiaeast' = 'aue1'
        'australiasoutheast' = 'aus1'
        'australiacentral' = 'auc1'
        'australiacentral2' = 'auc2'
        'southafricanorth' = 'zan1'
        'southafricawest' = 'zaw1'
        'uaenorth' = 'aen1'
        'uaecentral' = 'aec1'
        'qatarcentral' = 'qac1'
        'israelcentral' = 'ilc1'
        'jioindiacentral' = 'inc2'
        'jioindiawest' = 'inw2'
    }
}

# Handles Get-ProdicloudRegionCode.
function Get-ProdicloudRegionCode {
    param(
        [string]$Location
    )

    $normalized = if ($null -eq $Location) { '' } else { [string]$Location.Trim().ToLowerInvariant() }
    if ([string]::IsNullOrWhiteSpace($normalized)) {
        Throw-FriendlyError `
            -Detail "Region code could not be resolved because SELECTED_AZURE_REGION is empty." `
            -Code 22 `
            -Summary "Region code resolution failed." `
            -Hint "Set SELECTED_AZURE_REGION to a valid Azure region."
    }

    $map = Get-ProdicloudRegionCodeMap
    if ($map.ContainsKey($normalized)) {
        return [string]$map[$normalized]
    }

    Throw-FriendlyError `
        -Detail ("No static REGION_CODE mapping exists for region '{0}'." -f $normalized) `
        -Code 22 `
        -Summary "Region code resolution failed." `
        -Hint "Add the region to the built-in REGION_CODE map in modules/config/region/prodicloud-region-codes.ps1."
}
