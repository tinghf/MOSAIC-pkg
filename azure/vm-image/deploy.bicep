// ==============================================================================
// MOSAIC VM Deployment from Custom Image
// ==============================================================================
// Deploys a VM from the pre-configured MOSAIC image
//
// Usage:
//   az deployment group create \
//     --resource-group mosaic-rg \
//     --template-file deploy.bicep \
//     --parameters @parameters.json
// ==============================================================================

@description('Name of the VM')
param vmName string = 'mosaic-vm'

@description('VM size (HPC optimized for MOSAIC)')
@allowed([
  'Standard_HB120rs_v3'  // 120 cores, 448GB RAM (recommended)
  'Standard_HB120-96rs_v3'  // 96 cores, 448GB RAM
  'Standard_HB120-64rs_v3'  // 64 cores, 448GB RAM
  'Standard_D32s_v3'  // 32 cores, 128GB RAM (dev/testing)
  'Standard_D16s_v3'  // 16 cores, 64GB RAM (small runs)
])
param vmSize string = 'Standard_HB120rs_v3'

@description('Admin username')
param adminUsername string = 'mosaicuser'

@description('SSH public key')
@secure()
param sshPublicKey string

@description('Resource group containing the MOSAIC image')
param imageResourceGroup string = 'mosaic-images-rg'

@description('MOSAIC image name')
param imageName string = 'mosaic-ubuntu2004'

@description('Location for resources')
param location string = resourceGroup().location

@description('Enable RStudio Server access (port 8787)')
param enableRStudio bool = true

@description('Enable auto-shutdown at night (cost savings)')
param enableAutoShutdown bool = true

@description('Auto-shutdown time (UTC, 24h format)')
param shutdownTime string = '0200'

@description('Auto-shutdown timezone')
param shutdownTimezone string = 'UTC'

// Get existing image
resource mosaicImage 'Microsoft.Compute/images@2023-03-01' existing = {
  name: imageName
  scope: resourceGroup(imageResourceGroup)
}

// Create virtual network
resource vnet 'Microsoft.Network/virtualNetworks@2023-05-01' = {
  name: '${vmName}-vnet'
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.0.0.0/16'
      ]
    }
    subnets: [
      {
        name: 'default'
        properties: {
          addressPrefix: '10.0.0.0/24'
        }
      }
    ]
  }
}

// Create public IP
resource publicIP 'Microsoft.Network/publicIPAddresses@2023-05-01' = {
  name: '${vmName}-ip'
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
    dnsSettings: {
      domainNameLabel: vmName
    }
  }
}

// Create network security group
resource nsg 'Microsoft.Network/networkSecurityGroups@2023-05-01' = {
  name: '${vmName}-nsg'
  location: location
  properties: {
    securityRules: [
      {
        name: 'SSH'
        properties: {
          priority: 1000
          protocol: 'Tcp'
          access: 'Allow'
          direction: 'Inbound'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '22'
        }
      }
      {
        name: 'RStudio'
        properties: {
          priority: 1001
          protocol: 'Tcp'
          access: enableRStudio ? 'Allow' : 'Deny'
          direction: 'Inbound'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '8787'
        }
      }
    ]
  }
}

// Create network interface
resource nic 'Microsoft.Network/networkInterfaces@2023-05-01' = {
  name: '${vmName}-nic'
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          subnet: {
            id: vnet.properties.subnets[0].id
          }
          privateIPAllocationMethod: 'Dynamic'
          publicIPAddress: {
            id: publicIP.id
          }
        }
      }
    ]
    networkSecurityGroup: {
      id: nsg.id
    }
  }
}

// Create VM
resource vm 'Microsoft.Compute/virtualMachines@2023-03-01' = {
  name: vmName
  location: location
  properties: {
    hardwareProfile: {
      vmSize: vmSize
    }
    osProfile: {
      computerName: vmName
      adminUsername: adminUsername
      linuxConfiguration: {
        disablePasswordAuthentication: true
        ssh: {
          publicKeys: [
            {
              path: '/home/${adminUsername}/.ssh/authorized_keys'
              keyData: sshPublicKey
            }
          ]
        }
      }
    }
    storageProfile: {
      imageReference: {
        id: mosaicImage.id
      }
      osDisk: {
        createOption: 'FromImage'
        diskSizeGB: 256
        managedDisk: {
          storageAccountType: 'Premium_LRS'
        }
      }
      dataDisks: [
        {
          lun: 0
          createOption: 'Empty'
          diskSizeGB: 512
          managedDisk: {
            storageAccountType: 'Premium_LRS'
          }
        }
      ]
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: nic.id
        }
      ]
    }
  }
}

// Configure auto-shutdown schedule
resource autoShutdown 'Microsoft.DevTestLab/schedules@2018-09-15' = if (enableAutoShutdown) {
  name: 'shutdown-computevm-${vmName}'
  location: location
  properties: {
    status: 'Enabled'
    taskType: 'ComputeVmShutdownTask'
    dailyRecurrence: {
      time: shutdownTime
    }
    timeZoneId: shutdownTimezone
    notificationSettings: {
      status: 'Disabled'
    }
    targetResourceId: vm.id
  }
}

// Outputs
output vmId string = vm.id
output publicIp string = publicIP.properties.ipAddress
output fqdn string = publicIP.properties.dnsSettings.fqdn
output sshCommand string = 'ssh ${adminUsername}@${publicIP.properties.ipAddress}'
output rstudioUrl string = enableRStudio ? 'http://${publicIP.properties.ipAddress}:8787' : 'RStudio disabled'
output vmSize string = vmSize
output estimatedMonthlyCost string = vmSize == 'Standard_HB120rs_v3' ? '~$2,160/month if always on (730 hrs × $3.00/hr)' : 'See Azure pricing calculator'
