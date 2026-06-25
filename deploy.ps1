<#
.SYNOPSIS
    Script de despliegue de Terraform para AWS DevOps Agent
.DESCRIPTION
    Este script automatiza el despliegue de los recursos de AWS DevOps Agent
    utilizando Terraform. Verifica prerequisitos, inicializa Terraform,
    valida la configuración, y aplica el plan de despliegue.

    Flujo de ejecución:
    1. Verifica que Terraform y AWS CLI estén instalados
    2. Verifica que las credenciales de AWS estén configuradas
    3. Crea terraform.tfvars desde el ejemplo si no existe
    4. Inicializa y valida la configuración de Terraform
    5. Solicita confirmación antes de aplicar el despliegue
#>

#Requires -Version 5.1

$ErrorActionPreference = "Stop"

Write-Host "🚀 AWS DevOps Agent - Despliegue con Terraform" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

# Verificar prerequisitos
Write-Host "📋 Verificando prerequisitos..." -ForegroundColor Yellow

# Verificar si Terraform está instalado
if (-not (Get-Command terraform -ErrorAction SilentlyContinue)) {
    Write-Host "❌ Terraform no está instalado. Por favor instala Terraform primero." -ForegroundColor Red
    exit 1
}

# Verificar si AWS CLI está instalado
if (-not (Get-Command aws -ErrorAction SilentlyContinue)) {
    Write-Host "❌ AWS CLI no está instalado. Por favor instala AWS CLI primero." -ForegroundColor Red
    exit 1
}

# Verificar credenciales de AWS
aws sts get-caller-identity 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ Credenciales de AWS no configuradas. Ejecuta 'aws configure' primero." -ForegroundColor Red
    exit 1
}

Write-Host "✅ Verificación de prerequisitos exitosa" -ForegroundColor Green

# Crear terraform.tfvars si no existe
if (-not (Test-Path "terraform.tfvars")) {
    Write-Host "📝 Creando terraform.tfvars desde la plantilla..." -ForegroundColor Yellow
    Copy-Item "terraform.tfvars.example" "terraform.tfvars"
    Write-Host "✅ Por favor edita 'terraform.tfvars' con tu configuración específica" -ForegroundColor Green
    Write-Host "   Luego ejecuta este script nuevamente."
    exit 0
}

# Inicializar Terraform
Write-Host "🔧 Inicializando Terraform..." -ForegroundColor Yellow
terraform init
if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ Error al inicializar Terraform" -ForegroundColor Red
    exit 1
}

# Validar configuración
Write-Host "🔍 Validando configuración de Terraform..." -ForegroundColor Yellow
terraform validate
if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ Error en la validación de Terraform" -ForegroundColor Red
    exit 1
}

# Planificar despliegue
Write-Host "📋 Planificando despliegue..." -ForegroundColor Yellow
terraform plan -out=tfplan
if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ Error al planificar el despliegue" -ForegroundColor Red
    exit 1
}

# Solicitar confirmación
Write-Host "" 
$respuesta = Read-Host "🤔 ¿Deseas aplicar este plan? (s/N)"
if ($respuesta -ne "s" -and $respuesta -ne "S") {
    Write-Host "❌ Despliegue cancelado" -ForegroundColor Red
    Remove-Item -Path "tfplan" -ErrorAction SilentlyContinue
    exit 0
}

# Aplicar despliegue
Write-Host "🚀 Aplicando despliegue..." -ForegroundColor Cyan

terraform apply tfplan
if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ Despliegue falló" -ForegroundColor Red
    Write-Host "   Revisa los errores arriba e intenta ejecutar 'terraform apply' manualmente"
    Remove-Item -Path "tfplan" -ErrorAction SilentlyContinue
    exit 1
}

# Limpiar archivo del plan
Remove-Item -Path "tfplan" -ErrorAction SilentlyContinue

Write-Host ""
Write-Host "🎉 ¡Despliegue completado exitosamente!" -ForegroundColor Green
Write-Host ""
Write-Host "📋 Próximos pasos:" -ForegroundColor Yellow
Write-Host "1. Revisa los outputs arriba para obtener el ARN de tu Agent Space"
Write-Host "2. Visita https://console.aws.amazon.com/aidevops/ para acceder a la consola"
Write-Host ""
Write-Host "📋 Para monitoreo entre cuentas (Parte 2):" -ForegroundColor Yellow
Write-Host "1. Configura service_account_id en terraform.tfvars"
Write-Host "2. Configura agent_space_arn con el ARN del output anterior"
Write-Host "3. Configura el alias del proveedor aws.service con las credenciales de la cuenta de servicio"
Write-Host "4. Ejecuta './deploy.ps1' nuevamente"