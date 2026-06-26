# Configuración de Terraform para AWS DevOps Agent

Esta configuración de Terraform replica el [ejemplo de inicio rápido con CDK](https://github.com/aws-samples/sample-aws-devops-agent-cdk), proporcionando una configuración equivalente de Infraestructura como Código para desplegar recursos de AWS DevOps Agent.

## Descripción General

AWS DevOps Agent te ayuda a monitorear y gestionar tu infraestructura de AWS utilizando información basada en inteligencia artificial. Esta configuración automatiza el proceso descrito en la [guía de inicio](https://docs.aws.amazon.com/devopsagent/latest/userguide/getting-started-with-aws-devops-agent-getting-started-with-aws-devops-agent-using-terraform.html).

## Prerrequisitos

- Terraform >= 1.0
- AWS CLI configurado con los permisos adecuados
- Una cuenta de AWS para la cuenta de monitoreo (principal)
- (Opcional) Una segunda cuenta de AWS para monitoreo entre cuentas

### Configuración de Autenticación AWS

Antes de ejecutar los scripts de despliegue, debes autenticarte en AWS. Existen varias formas de hacerlo:

#### Opción 1: AWS CLI con Access Keys (recomendado para desarrollo local)

```bash
aws configure
```
Te solicitará:
- **AWS Access Key ID** y **AWS Secret Access Key**: Credenciales de un usuario IAM con permisos suficientes (ver sección "Permisos IAM Requeridos").
- **Default region**: `us-east-1` (o la región donde deseas desplegar).
- **Default output format**: `json`

#### Opción 2: Perfil nombrado

```bash
aws configure --profile devops-agent
```
Luego configura la variable de entorno o el proveedor de Terraform para usar ese perfil:
```bash
export AWS_PROFILE=devops-agent   # Linux/macOS
$env:AWS_PROFILE = "devops-agent" # Windows PowerShell
```

#### Opción 3: Rol de asunción (assume role)

Si usas un rol cross-account o un rol de administración, puedes configurar un perfil que asuma un rol:

```ini
# ~/.aws/config
[profile devops-admin]
region = us-east-1
role_arn = arn:aws:iam::<CUENTA_MONITOREO>:role/NombreDelRol
source_profile = default
```

#### Opción 4: Variables de entorno

```bash
export AWS_ACCESS_KEY_ID=AKIAXXXXXXXX
export AWS_SECRET_ACCESS_KEY=xxxxxxxx
export AWS_DEFAULT_REGION=us-east-1
```
```powershell
# Windows PowerShell
$env:AWS_ACCESS_KEY_ID = "AKIAXXXXXXXX"
$env:AWS_SECRET_ACCESS_KEY = "xxxxxxxx"
$env:AWS_DEFAULT_REGION = "us-east-1"
```

> **Nota:** Los scripts `deploy.sh` y `deploy.ps1` verifican la autenticación ejecutando `aws sts get-caller-identity`. Si este comando falla, los scripts mostrarán un error y se detendrán.

### Permisos IAM Requeridos

Para desplegar todos los recursos de este proyecto, la identidad AWS (usuario o rol) utilizada para ejecutar Terraform debe tener los siguientes permisos:

#### Parte 1 — Permisos en la Cuenta de Monitoreo

| Permiso IAM | Recurso | Propósito |
|-------------|---------|-----------|
| `iam:CreateRole` | `arn:aws:iam::*:role/DevOpsAgentRole-*` | Crear roles IAM del Agent Space y Operador |
| `iam:DeleteRole` | `arn:aws:iam::*:role/DevOpsAgentRole-*` | Eliminar roles IAM durante limpieza |
| `iam:GetRole` | `*` | Leer roles IAM existentes |
| `iam:PassRole` | `arn:aws:iam::*:role/DevOpsAgentRole-*` | Pasar roles al servicio DevOps Agent |
| `iam:AttachRolePolicy` | `arn:aws:iam::*:role/DevOpsAgentRole-*` | Adjuntar políticas administradas a roles |
| `iam:DetachRolePolicy` | `arn:aws:iam::*:role/DevOpsAgentRole-*` | Desadjuntar políticas durante limpieza |
| `iam:PutRolePolicy` | `arn:aws:iam::*:role/DevOpsAgentRole-*` | Crear políticas inline en roles |
| `iam:DeleteRolePolicy` | `arn:aws:iam::*:role/DevOpsAgentRole-*` | Eliminar políticas inline durante limpieza |
| `aidevops:CreateAgentSpace` | `*` | Crear el Agent Space |
| `aidevops:DeleteAgentSpace` | `*` | Eliminar el Agent Space |
| `aidevops:GetAgentSpace` | `*` | Leer configuración del Agent Space |
| `aidevops:CreateAssociation` | `*` | Asociar cuentas al Agent Space |
| `aidevops:DeleteAssociation` | `*` | Eliminar asociaciones |
| `iam:CreateServiceLinkedRole` | `arn:aws:iam::*:role/aws-service-role/resource-explorer-2.amazonaws.com/AWSServiceRoleForResourceExplorer` | Crear rol vinculado de Resource Explorer |
| `sts:GetCallerIdentity` | `*` | Verificar identidad AWS (usado por los scripts) |

#### Parte 2 — Permisos Adicionales en la Cuenta de Servicio (Secundaria)

Si implementas monitoreo cross-account (Parte 2), la identidad utilizada en el **proveedor `aws.service`** debe tener estos permisos en la cuenta secundaria:

| Permiso IAM | Recurso | Propósito |
|-------------|---------|-----------|
| `iam:CreateRole` | `arn:aws:iam::*:role/DevOpsAgentRole-*` | Crear rol cross-account |
| `iam:CreateRole` | `arn:aws:iam::*:role/echo-service-tf-role` | Crear rol de ejecución de Lambda |
| `iam:AttachRolePolicy` | `arn:aws:iam::*:role/DevOpsAgentRole-*` | Adjuntar política al rol cross-account |
| `iam:AttachRolePolicy` | `arn:aws:iam::*:role/echo-service-tf-role` | Adjuntar política al rol de Lambda |
| `iam:PassRole` | `arn:aws:iam::*:role/echo-service-tf-role` | Pasar rol a Lambda |
| `lambda:CreateFunction` | `*` | Crear función Lambda echo |
| `lambda:DeleteFunction` | `*` | Eliminar función Lambda |
| `lambda:InvokeFunction` | `*` | Invocar función Lambda para pruebas |
| `iam:CreateServiceLinkedRole` | `arn:aws:iam::*:role/aws-service-role/resource-explorer-2.amazonaws.com/AWSServiceRoleForResourceExplorer` | Crear rol vinculado de Resource Explorer |

#### Política Administrada Recomendada

Para simplificar, puedes usar la política administrada de AWS **`AdministratorAccess`** (o `arn:aws:iam::aws:policy/AdministratorAccess`) en un entorno de desarrollo o pruebas. Para entornos productivos, se recomienda crear una política personalizada con los permisos específicos listados arriba.

#### Verificación de Permisos

Puedes verificar que tu identidad AWS tiene los permisos necesarios ejecutando:

```bash
# Verificar identidad actual
aws sts get-caller-identity

# Verificar que puedes crear roles IAM (simulado)
aws iam create-role --role-name test-permissions --assume-role-policy-document '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"ec2.amazonaws.com"},"Action":"sts:AssumeRole"}]}' --no-cli-pager

# Limpiar el rol de prueba
aws iam delete-role --role-name test-permissions
```

## Qué cubre esta guía

Esta guía está dividida en dos partes:

- **Parte 1** — Implementa un espacio de agente (agent space) con una aplicación operadora y una asociación de AWS en tu cuenta de monitoreo. Después de completar esta parte, el agente puede monitorear problemas en esa cuenta.
- **Parte 2 (Opcional)** — Agrega una asociación de AWS de origen para una cuenta de servicio e implementa un rol IAM entre cuentas junto con una función Lambda de eco en esa cuenta.

## Recursos Creados

### Parte 1: Cuenta de Monitoreo

| Recurso | Nombre | Propósito |
|---------|--------|-----------|
| Agent Space | Configurable | Espacio de agente central con aplicación operadora |
| Rol IAM | DevOpsAgentRole-AgentSpace-* | Asumido por el agente para monitorear la cuenta. Utiliza la política administrada `AIDevOpsAgentAccessPolicy`. |
| Rol IAM | DevOpsAgentRole-WebappAdmin-* | Rol de la aplicación operadora. Utiliza la política administrada `AIDevOpsOperatorAppAccessPolicy`. |
| Asociación | AWS (monitor) | Vincula la cuenta de monitoreo |
| Asociación | AWS (source) | Vincula la cuenta de servicio (opcional) |

### Parte 2: Cuenta de Servicio (Opcional)

| Recurso | Nombre | Propósito |
|---------|--------|-----------|
| Rol IAM | DevOpsAgentRole-SecondaryAccount-TF | Rol entre cuentas con confianza del Agent Space. Utiliza la política administrada `AIDevOpsAgentAccessPolicy`. |
| Lambda | echo-service-tf | Servicio de ejemplo |

> **🔍 Detalle técnico:** Consulta [`help-recursos-adicionales.md`](help-recursos-adicionales.md) para una explicación detallada de todos los recursos desplegados en la cuenta secundaria (rol cross-account, Lambda echo, políticas IAM).

## Uso

### Parte 1: Implementar el Agent Space

1. **Clonar y configurar**
   ```bash
   git clone <this-repo>
   cd SampleTerraformdeploy-AWSDevosAgent
   cp terraform.tfvars.example terraform.tfvars
   ```

2. **Editar `terraform.tfvars`** con el nombre y la descripción de tu agent space.

3. **Implementar**
   ```bash
   ./deploy.sh          # Linux/macOS
   .\deploy.ps1         # Windows (PowerShell)
   ```
   O manualmente:
   ```bash
   terraform init
   terraform plan
   terraform apply
   ```

4. **Registrar las salidas** — anota el valor de `agent_space_arn` para la Parte 2.

5. **Verificar**
   ```bash
   ./post-deploy.sh     # Linux/macOS
   .\post-deploy.ps1    # Windows (PowerShell)
   ```

### Parte 2 (Opcional): Agregar Monitoreo entre Cuentas

1. **Establecer el ID de la cuenta de servicio** en `terraform.tfvars`:
   ```hcl
   service_account_id = "<ID_DE_TU_CUENTA_DE_SERVICIO>"
   ```

2. **Establecer el ARN del agent space** obtenido de la salida de la Parte 1:
   ```hcl
   agent_space_arn = "arn:aws:aidevops:us-east-1:<ID_CUENTA_MONITOREO>:agentspace/<ID_ESPACIO>"
   ```

3. **Configurar el proveedor `aws.service`** en `main.tf` con las credenciales para la cuenta de servicio. Puedes usar un perfil nombrado o un rol de asunción:

   Usando un perfil:
   ```hcl
   provider "aws" {
     alias   = "service"
     region  = var.aws_region
     profile = "tu-perfil-cuenta-servicio"
   }
   ```

   O usando un rol de asunción:
   ```hcl
   provider "aws" {
     alias  = "service"
     region = var.aws_region
     assume_role {
       role_arn = "arn:aws:iam::<ID_CUENTA_SERVICIO>:role/OrganizationAccountAccessRole"
     }
   }
   ```

4. **Implementar nuevamente**:
   ```bash
   terraform apply
   ```
   O usando los scripts automatizados:
   ```bash
   ./deploy.sh          # Linux/macOS
   .\deploy.ps1         # Windows (PowerShell)
   ```

5. **Probar el servicio echo**:
   ```bash
   aws lambda invoke \
     --function-name echo-service-tf \
     --payload '{"test": "hello world"}' \
     --profile service \
     --region us-east-1 \
     response.json
   cat response.json
   ```

## Opciones de Configuración

| Variable | Descripción | Valor por Defecto |
|----------|-------------|-------------------|
| `aws_region` | Región de AWS para el despliegue | `us-east-1` |
| `agent_space_name` | Nombre para el Agent Space | `MyAgentSpace` |
| `agent_space_description` | Descripción para el Agent Space | `AgentSpace for monitoring my application` |
| `service_account_id` | ID de la cuenta de servicio para monitoreo entre cuentas | `""` |
| `agent_space_arn` | ARN del Agent Space (requerido para la Parte 2) | `""` |
| `name_postfix` | Sufijo para los nombres de los roles IAM | `""` |
| `tags` | Etiquetas para todos los recursos | Ver variables.tf |

## Solución de Problemas

- Retrasos en la propagación de IAM: La configuración incluye un `time_sleep` de 30 segundos entre la creación del rol IAM y la creación del Agent Space. El servicio DevOps Agent valida la política de confianza del rol operador durante la creación del Agent Space, y esto puede fallar si IAM no se ha propagado completamente. Si aún ves errores de política de confianza, espera un minuto y ejecuta `terraform apply` nuevamente — los roles IAM ya existirán y el apply continuará desde donde se quedó.

> **📖 Para más detalles:** Revisa [`help-devopsagent.md`](help-devopsagent.md) para entender el flujo completo de dependencias y el rol del `time_sleep`, y [`help-recursos-adicionales.md`](help-recursos-adicionales.md) para comprender las políticas de confianza IAM y las condiciones de seguridad.

## Limpieza

Destruye en orden inverso si implementaste la Parte 2:
```bash
./cleanup.sh           # Linux/macOS
.\cleanup.ps1          # Windows (PowerShell)
```
O manualmente:
```bash
terraform destroy
```

## Scripts Automatizados

Este repositorio incluye scripts automatizados para facilitar el despliegue, verificación y limpieza. Están disponibles en dos formatos según tu sistema operativo:

| Función | Linux/macOS (bash) | Windows (PowerShell) |
|---------|-------------------|---------------------|
| Despliegue | `./deploy.sh` | `.\deploy.ps1` |
| Verificación post-despliegue | `./post-deploy.sh` | `.\post-deploy.ps1` |
| Limpieza | `./cleanup.sh` | `.\cleanup.ps1` |

## Archivos de Documentación Complementaria

Este repositorio incluye los siguientes archivos markdown con documentación técnica detallada:

| Archivo | Contenido |
|---------|-----------|
| [`help-devopsagent.md`](help-devopsagent.md) | Explicación detallada de `deploy-devopsagent.tf`: Agent Space, asociaciones primaria y secundaria, `time_sleep` para propagación IAM, diagrama de flujo completo y arquitectura general. |
| [`help-recursos-adicionales.md`](help-recursos-adicionales.md) | Explicación detallada de `iam.tf` (roles IAM, políticas de confianza, políticas administradas e inline), `serviceaccount.tf` (recursos cross-account: rol secundario, Lambda echo, roles de ejecución) y `terraform.tfvars.example` (variables de configuración). |

## Referencias y Mejores Prácticas

- **Guía oficial de inicio rápido con Terraform:** [Getting started with AWS DevOps Agent using Terraform](https://docs.aws.amazon.com/devopsagent/latest/userguide/getting-started-with-aws-devops-agent-getting-started-with-aws-devops-agent-using-terraform.html) — Documentación oficial de AWS que cubre los pasos iniciales para configurar AWS DevOps Agent con Terraform.

- **Mejores prácticas para entornos productivos:** [Best Practices for deploying AWS DevOps Agent in production](https://aws.amazon.com/es/blogs/devops/best-practices-for-deploying-aws-devops-agent-in-production/) — Publicado en el blog de AWS DevOps, cubre aspectos clave como configuración de IAM, monitoreo multi-cuenta, seguridad y optimización de recursos.

- **Arquitectura, funcionamiento y demo de AWS DevOps Agent:** [AWS DevOps Agent Explained: Architecture, Setup, and Real Root Cause Demo (CloudWatch, EKS)](https://dev.to/aws-builders/aws-devops-agent-explained-architecture-setup-and-real-root-cause-demo-cloudwatch-eks-ng7) — Artículo en dev.to que explica la arquitectura interna, el proceso de discovery, la configuración paso a paso y una demostración práctica de análisis de causa raíz con CloudWatch y EKS.

- **Detección de desviación de infraestructura con Terraform State MCP Server:** [Terraform State MCP Server for Amazon DevOps Agent](https://github.com/aws-samples/sample-devops-agent-terraform-mcp/tree/main) — Repositorio de ejemplo de AWS que implementa un servidor MCP (Model Context Protocol) para que DevOps Agent detecte cambios de arquitectura (drift) comparando el estado de Terraform (tfstate) contra los recursos en vivo de AWS y Kubernetes. Incluye una función Lambda que descubre automáticamente archivos `.tfstate` desde buckets S3 etiquetados, los filtra y los expone al agente para su análisis.

## Licencia

Este proyecto está licenciado bajo la Licencia MIT - consulta el archivo LICENSE para más detalles.
