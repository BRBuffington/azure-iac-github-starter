using './bot-service.bicep'

param botName = 'bot-foundry-agent-eus-prd-001'
param agentPrincipalId = '00000000-0000-0000-0000-000000000000'
param tenantId = '11111111-1111-1111-1111-111111111111'
param activityEndpoint = 'https://clientfoundry.services.ai.azure.com/api/projects/clientagent/agents/client-agent/endpoint/protocols/activityProtocol?api-version=2025-05-15-preview'