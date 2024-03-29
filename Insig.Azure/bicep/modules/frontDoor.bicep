param projectName string
param environment string
param webAppName string
param appServiceName string
param storageName string
param frontDoorProfileName string
param wafEnableLimitToPoland bool

resource frontDoorProfile 'Microsoft.Cdn/profiles@2023-05-01' existing = {
  name: frontDoorProfileName
}

resource frontDoorWafPolicy 'Microsoft.Network/FrontDoorWebApplicationFirewallPolicies@2022-05-01' = {
  name: '${projectName}${environment}waf'
  location: 'global'
  sku: {
    name: 'Standard_AzureFrontDoor'
  }
  properties: {
    policySettings: {
      enabledState: 'Enabled'
      mode: 'Detection'
      requestBodyCheck: 'Enabled'
    }
    customRules: {
      rules: [
        {
          action: 'Block'
          matchConditions: [
            {
              matchValue: [
                '0'
              ]
              matchVariable: 'RequestUri'
              negateCondition: false
              operator: 'GreaterThan'
            }
          ]
          name: 'RateLimit'
          priority: 100
          rateLimitDurationInMinutes: 1
          rateLimitThreshold: 100
          ruleType: 'RateLimitRule'
        }
        {
          action: 'Block'
          enabledState: wafEnableLimitToPoland ? 'Enabled' : 'Disabled'
          matchConditions: [
            {
              matchValue: [
                'PL'
                'ZZ'
              ]
              matchVariable: 'SocketAddr'
              negateCondition: true
              operator: 'GeoMatch'
            }
          ]
          name: 'LimitToPoland'
          priority: 150
          ruleType: 'MatchRule'
        }
      ]
    }
  }
}

resource ruleSet 'Microsoft.Cdn/profiles/ruleSets@2023-05-01' = {
  name: 'Default'
  parent: frontDoorProfile
}

resource rules 'Microsoft.Cdn/profiles/ruleSets/rules@2023-05-01' = {
  name: 'CSP'
  parent: ruleSet
  properties: {
    actions: [
      {
        name: 'ModifyResponseHeader'
        parameters: {
          headerAction: 'Append'
          headerName: 'Content-Security-Policy-Report-Only'
          typeName: 'DeliveryRuleHeaderActionParameters'
          value: 'default-src \'self\' ${frontDoorStaticWebConfig.outputs.frontDoorEndpointHostmane} *.${frontDoorStaticWebConfig.outputs.frontDoorEndpointHostmane};style-src \'self\' \'unsafe-inline\' https://fonts.googleapis.com;font-src \'self\' https://fonts.googleapis.com https://fonts.gstatic.com'
        }
      }
    ]
  }
}

resource webApp 'Microsoft.Web/staticSites@2023-01-01' existing = {
  name: webAppName
}

resource appService 'Microsoft.Web/sites@2023-01-01' existing = {
  name: appServiceName
}

resource storage 'Microsoft.Storage/storageAccounts@2023-01-01' existing = {
  name: storageName
}

module frontDoorStaticWebConfig 'frontDoorConfig.bicep' = {
  name: '${projectName}-web-front-door'
  params: {
    name: 'StaticWebApp'
    frontDoorProfileName: frontDoorProfile.name
    frontDoorEndpointName: webAppName
    originHostName: webApp.properties.defaultHostname
    originHostHeader: webApp.properties.defaultHostname
    useCaching: true
    ruleSets: [
      {
        id: ruleSet.id
      }
    ]
  }
}

module frontDoorAppServiceConfig 'frontDoorConfig.bicep' = {
  name: '${projectName}-api-front-door'
  params: {
    name: 'AppService'
    frontDoorProfileName: frontDoorProfile.name
    frontDoorEndpointName: appServiceName
    originHostName: appService.properties.defaultHostName
    originHostHeader: appService.properties.defaultHostName
  }
}

var blobEndpointHostname = replace(replace(storage.properties.primaryEndpoints.blob, 'https://', ''), '/', '')

module frontDoorStorageConfig 'frontDoorConfig.bicep' = {
  name: '${projectName}-storage-front-door'
  params: {
    name: 'Storage'
    frontDoorProfileName: frontDoorProfile.name
    frontDoorEndpointName: storageName
    originHostName: blobEndpointHostname
    originHostHeader: blobEndpointHostname
    useCaching: true
  }
}

resource securityPolicy 'Microsoft.Cdn/profiles/securityPolicies@2023-05-01' = {
  parent: frontDoorProfile
  name: '${projectName}${environment}SecurityPolicy'
  properties: {
    parameters: {
      type: 'WebApplicationFirewall'
      wafPolicy: {
        id: frontDoorWafPolicy.id
      }
      associations: [
        {
          domains: [
            {
              id: frontDoorStaticWebConfig.outputs.frontDoorEndpointId
            }
            {
              id: frontDoorAppServiceConfig.outputs.frontDoorEndpointId
            }
            {
              id: frontDoorStorageConfig.outputs.frontDoorEndpointId
            }
          ]
          patternsToMatch: [
            '/*'
          ]
        }
      ]
    }
  }
}
