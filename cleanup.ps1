<#
.SYNOPSIS
    Script de limpieza de Terraform para AWS DevOps Agent
.DESCRIPTION
    Este script destruye todos los recursos de AWS DevOps Agent creados
    por Terraform de forma segura, solicitando doble confirmación antes
    de proceder con la destrucción.

    Flujo de ejecución:
    1. Verifica que exista el archivo de estado de Terraform
    2. Muestra el plan de destrucción
    3. Solicita primera confirmación
    4. Solicita segunda confirmación escribiendo "DESTROY"
    5. Ejecuta terraform destroy para eliminar todos los recursos
#>

#Requires -Version 5.1

$ErrorActionPreference = "Stop"

Write-Host "🧹 AWS DevOps Agent - Limpieza con Terraform" -ForegroundColor Cyan
Write-Host "=====================================" -ForegroundColor Cyan

# Verificar si existe el archivo de estado de Terraform
if (-not (Test-Path "terraform.tfstate")) {
    Write-Host "❌ No se encontró el archivo de estado de Terraform. No hay nada que limpiar." -ForegroundColor Red
    exit 0
}

# Mostrar lo que se destruirá
Write-Host "🔍 Planificando destrucción..." -ForegroundColor Yellow
terraform plan -destroy
if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ Error al planificar la destrucción" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "⚠️  ADVERTENCIA: ¡Esto destruirá todos los recursos de AWS DevOps Agent!" -ForegroundColor Red
Write-Host "   - Agent Space y todas las asociaciones" -ForegroundColor Red
Write-Host "   - Roles y políticas IAM" -ForegroundColor Red
Write-Host "   - Todas las configuraciones de monitoreo" -ForegroundColor Red
Write-Host "   - (Si aplica) Recursos de la cuenta secundaria (rol cross-account, Lambda echo)" -ForegroundColor Red
Write-Host ""

$respuesta = Read-Host "🤔 ¿Estás seguro de que deseas destruir todo? (s/N)"
if ($respuesta -ne "s" -and $respuesta -ne "S") {
    Write-Host "❌ Limpieza cancelada" -ForegroundColor Red
    exit 0
}

Write-Host ""
$confirmacion = Read-Host "🚨 ¡Última oportunidad! Escribe 'DESTROY' para confirmar"
if ($confirmacion -ne "DESTROY") {
    Write-Host "❌ Limpieza cancelada" -ForegroundColor Red
    exit 0
}

# Destruir recursos
Write-Host "🧹 Destruyendo recursos..." -ForegroundColor Yellow
terraform destroy -auto-approve
if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ Error durante la destrucción de recursos" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "✅ ¡Limpieza completada exitosamente!" -ForegroundColor Green
Write-Host "   Todos los recursos de AWS DevOps Agent han sido eliminados."