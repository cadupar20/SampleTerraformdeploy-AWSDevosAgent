# Configuración de Terraform para AWS DevOps Agent

Esta configuración de Terraform replica el [ejemplo de inicio rápido con CDK](https://github.com/aws-samples/sample-aws-devops-agent-cdk), proporcionando una configuración equivalente de Infraestructura como Código para desplegar recursos de AWS DevOps Agent.

## Descripción General

AWS DevOps Agent te ayuda a monitorear y gestionar tu infraestructura de AWS utilizando información basada en inteligencia artificial. Esta configuración automatiza el proceso descrito en la [guía de inicio](https://docs.aws.amazon.com/devopsagent/latest/userguide/getting-started-with-aws-devops-agent-getting-started-with-aws-devops-agent-using-terraform.html).

## Prerrequisitos

- Terraform >= 1.0
- AWS CLI configurado con los permisos adecuados
- Una cuenta de AWS para la cuenta de monitoreo (principal)
- (Opcional) Una segunda cuenta de AWS para monitoreo entre cuentas

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
   cd sample-aws-devops-agent-terraform
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

## Licencia

Este proyecto está licenciado bajo la Licencia MIT - consulta el archivo LICENSE para más detalles.
