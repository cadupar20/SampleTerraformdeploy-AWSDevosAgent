<#
.SYNOPSIS
    Script de verificación post-despliegue para AWS DevOps Agent
.DESCRIPTION
    Este script obtiene los outputs de Terraform después del despliegue
    y muestra comandos de verificación para confirmar que el Agent Space
    y las asociaciones se crearon correctamente.

    Flujo de ejecución:
    1. Obtiene los outputs de Terraform (ID del Agent Space, ARN, roles)
    2. Muestra comandos de AWS CLI para verificar el estado
    3. Proporciona la URL de la consola de DevOps Agent
#>

#Requires -Version 5.1

$ErrorActionPreference = "Stop"

Write-Host "🔍 AWS DevOps Agent - Verificación Post-Despliegue" -ForegroundColor Cyan
Write-Host "=================================================" -ForegroundColor Cyan

# Obtener outputs de Terraform
Write-Host "📋 Obteniendo outputs de Terraform..." -ForegroundColor Yellow

$AGENT_SPACE_ID = terraform output -raw agent_space_id 2>$null
if (-not $AGENT_SPACE_ID) {
    Write-Host "❌ No se pudo obtener el ID del Agent Space desde los outputs de Terraform" -ForegroundColor Red
    Write-Host "   Asegúrate de que Terraform se haya aplicado exitosamente"
    exit 1
}

$AGENT_SPACE_ARN = terraform output -raw agent_space_arn 2>$null
$AGENTSPACE_ROLE_ARN = terraform output -raw devops_agentspace_role_arn 2>$null
$OPERATOR_ROLE_ARN = terraform output -raw devops_operator_role_arn 2>$null
$REGION = terraform output -raw aws_region 2>$null
if (-not $REGION) {
    $REGION = "us-east-1"
}

Write-Host "✅ ID del Agent Space:       $AGENT_SPACE_ID" -ForegroundColor Green
Write-Host "✅ ARN del Agent Space:      $AGENT_SPACE_ARN" -ForegroundColor Green
Write-Host "✅ ARN del Rol Agent Space:  $AGENTSPACE_ROLE_ARN" -ForegroundColor Green
Write-Host "✅ ARN del Rol Operador:     $OPERATOR_ROLE_ARN" -ForegroundColor Green

Write-Host ""
Write-Host "🔍 Verifica tu configuración con los siguientes comandos:" -ForegroundColor Yellow
Write-Host ""
Write-Host "aws devops-agent get-agent-space --agent-space-id $AGENT_SPACE_ID --region $REGION"
Write-Host ""
Write-Host "aws devops-agent list-associations --agent-space-id $AGENT_SPACE_ID --region $REGION"
Write-Host ""
Write-Host "📋 Accede a la consola de DevOps Agent en:" -ForegroundColor Yellow
Write-Host "   https://console.aws.amazon.com/aidevops/"