# Explicación Detallada de Recursos Adicionales de Terraform

Este documento explica en detalle los archivos `iam.tf`, `serviceaccount.tf` y `terraform.tfvars.example`, describiendo el propósito de cada bloque de Terraform y cómo se integran en la arquitectura general de AWS DevOps Agent.

---

## 1. Archivo `iam.tf` — Roles y Políticas IAM

Este archivo define los roles IAM necesarios para que el servicio AWS DevOps Agent pueda operar y monitorear recursos en la cuenta de AWS.

### 1.1. `random_id.suffix` — Sufijo Aleatorio

```hcl
resource "random_id" "suffix" {
  byte_length = 4
}
```

**Propósito:** Genera un sufijo hexadecimal aleatorio de 4 bytes (8 caracteres) para garantizar que los nombres de los roles IAM sean únicos a nivel global. AWS requiere que los nombres de roles sean únicos dentro de una cuenta, y este sufijo evita conflictos de nombres.

---

### 1.2. `data.aws_iam_policy_document.devops_agentspace_trust` — Política de Confianza del Rol AgentSpace

```hcl
data "aws_iam_policy_document" "devops_agentspace_trust" {
  statement {
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["aidevops.amazonaws.com"]
    }
    actions = ["sts:AssumeRole"]
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = ["arn:aws:aidevops:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:agentspace/*"]
    }
  }
}
```

**Propósito:** Define **quién puede asumir** el rol `devops_agentspace`.

- **Principal:** El servicio `aidevops.amazonaws.com` (AWS DevOps Agent) puede asumir este rol.
- **Acción:** `sts:AssumeRole` — permite al servicio asumir el rol temporalmente.
- **Condiciones de seguridad:**
  - `aws:SourceAccount`: Solo permite solicitudes provenientes de la misma cuenta de AWS.
  - `aws:SourceArn`: Solo permite solicitudes que vengan de un Agent Space (`agentspace/*`) dentro de la misma región y cuenta.

> **¿Por qué es importante?** Estas condiciones evitan que el rol sea asumido desde cuentas externas o Agent Spaces no autorizados (confused deputy problem).

---

### 1.3. `aws_iam_role.devops_agentspace` — Rol del Agent Space

```hcl
resource "aws_iam_role" "devops_agentspace" {
  name               = "DevOpsAgentRole-AgentSpace-${var.name_postfix != "" ? var.name_postfix : random_id.suffix.hex}"
  assume_role_policy = data.aws_iam_policy_document.devops_agentspace_trust.json
  tags = var.tags
}
```

**Propósito:** Crea el rol IAM que el **DevOps Agent asumirá** para monitorear los recursos de la cuenta.

- **Nombre:** Sigue el patrón `DevOpsAgentRole-AgentSpace-<sufijo>`. Si se proporciona `name_postfix` se usa ese valor; de lo contrario usa el sufijo aleatorio.
- **Política de confianza:** La definida en el bloque anterior.
- **Tags:** Hereda las etiquetas definidas en `var.tags`.

**En la arquitectura:** Este es el rol que aparece en `deploy-devopsagent.tf` como `assumable_role_arn` en la asociación de la cuenta primaria.

---

### 1.4. `aws_iam_role_policy_attachment.devops_agentspace_access` — Política Administrada para AgentSpace

```hcl
resource "aws_iam_role_policy_attachment" "devops_agentspace_access" {
  role       = aws_iam_role.devops_agentspace.name
  policy_arn = "arn:aws:iam::aws:policy/AIDevOpsAgentAccessPolicy"
}
```

**Propósito:** Adjunta la **política administrada de AWS** `AIDevOpsAgentAccessPolicy` al rol del Agent Space.

- **¿Qué hace esta política?** Concede permisos al agente para acceder y monitorear recursos de AWS como EC2, Lambda, CloudWatch, etc.
- Es una política administrada por AWS, lo que significa que AWS la mantiene actualizada automáticamente a medida que agrega nuevos servicios y capacidades.

---

### 1.5. `data.aws_iam_policy_document.devops_agentspace_inline` — Política Inline para Resource Explorer

```hcl
data "aws_iam_policy_document" "devops_agentspace_inline" {
  statement {
    sid    = "AllowCreateServiceLinkedRoles"
    effect = "Allow"
    actions = ["iam:CreateServiceLinkedRole"]
    resources = [
      "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/aws-service-role/resource-explorer-2.amazonaws.com/AWSServiceRoleForResourceExplorer"
    ]
  }
}
```

**Propósito:** Permite al rol crear el **service-linked role** de AWS Resource Explorer.

- **¿Por qué es necesario?** El DevOps Agent utiliza Resource Explorer para descubrir recursos en la cuenta. Resource Explorer requiere un service-linked role (`AWSServiceRoleForResourceExplorer`) que debe ser creado por una entidad con permisos `iam:CreateServiceLinkedRole`.
- **Recurso específico:** Solo permite crear ese rol en particular, siguiendo el principio de mínimo privilegio.

---

### 1.6. `aws_iam_role_policy.devops_agentspace_inline` — Recurso de Política Inline

```hcl
resource "aws_iam_role_policy" "devops_agentspace_inline" {
  name   = "AllowCreateServiceLinkedRoles"
  role   = aws_iam_role.devops_agentspace.id
  policy = data.aws_iam_policy_document.devops_agentspace_inline.json
}
```

**Propósito:** Materializa la política inline definida anteriormente y la asocia al rol del Agent Space.

---

### 1.7. `data.aws_iam_policy_document.devops_operator_trust` — Política de Confianza del Rol Operador

```hcl
data "aws_iam_policy_document" "devops_operator_trust" {
  statement {
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["aidevops.amazonaws.com"]
    }
    actions = ["sts:AssumeRole", "sts:TagSession"]
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = ["arn:aws:aidevops:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:agentspace/*"]
    }
  }
}
```

**Propósito:** Define quién puede asumir el rol del **operador** (aplicación web).

- **Diferencia clave con el rol AgentSpace:** Incluye la acción `sts:TagSession`, que permite etiquetar la sesión asumida. Esto es necesario para que la aplicación operadora pueda transmitir contexto (como el usuario que realiza la acción) a través de las sesiones de AWS.

---

### 1.8. `aws_iam_role.devops_operator` — Rol del Operador (Webapp Admin)

```hcl
resource "aws_iam_role" "devops_operator" {
  name               = "DevOpsAgentRole-WebappAdmin-${var.name_postfix != "" ? var.name_postfix : random_id.suffix.hex}"
  assume_role_policy = data.aws_iam_policy_document.devops_operator_trust.json
  tags = var.tags
}
```

**Propósito:** Crea el rol IAM que usará la **aplicación operadora** (interfaz web) del DevOps Agent.

- **Nombre:** Sigue el patrón `DevOpsAgentRole-WebappAdmin-<sufijo>`.
- **Uso:** Este rol se asigna al `operator_app` dentro del recurso `awscc_devopsagent_agent_space` en `deploy-devopsagent.tf`.

---

### 1.9. `aws_iam_role_policy_attachment.devops_operator_access` — Política Administrada para Operador

```hcl
resource "aws_iam_role_policy_attachment" "devops_operator_access" {
  role       = aws_iam_role.devops_operator.name
  policy_arn = "arn:aws:iam::aws:policy/AIDevOpsOperatorAppAccessPolicy"
}
```

**Propósito:** Adjunta la política administrada `AIDevOpsOperatorAppAccessPolicy` al rol del operador.

- **¿Qué permisos otorga?** Permite a la aplicación operadora visualizar información de monitoreo, acceder al dashboard del DevOps Agent y realizar acciones operativas a través de la interfaz web.

---

## 2. Archivo `serviceaccount.tf` — Recursos para Cuenta de Servicio (Cross-Account)

Este archivo despliega recursos en una **cuenta secundaria** para habilitar el monitoreo entre cuentas (cross-account). Todos los recursos en este archivo son **condicionales** — solo se crean cuando `var.agent_space_arn` tiene un valor (después del despliegue inicial de la Parte 1).

### 2.1. Recurso Condicional `count`

Todos los recursos en este archivo usan `count = var.agent_space_arn != "" ? 1 : 0`. Esto significa:

- **Si `agent_space_arn` está vacío** (despliegue inicial): No se crea ningún recurso de cuenta secundaria.
- **Si `agent_space_arn` tiene un valor** (después de la Parte 1): Se crean los recursos para monitoreo cross-account.

---

### 2.2. `data.aws_iam_policy_document.secondary_account_trust` — Política de Confianza de Cuenta Secundaria

```hcl
data "aws_iam_policy_document" "secondary_account_trust" {
  count = var.agent_space_arn != "" ? 1 : 0

  statement {
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["aidevops.amazonaws.com"]
    }
    actions = ["sts:AssumeRole"]
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceArn"
      values   = [var.agent_space_arn]
    }
  }
}
```

**Propósito:** Define la política de confianza para el rol de la cuenta secundaria.

- **Diferencia clave con el rol primario:** La condición `aws:SourceArn` usa el **ARN exacto del Agent Space** (`var.agent_space_arn`) en lugar de un comodín (`*`). Esto garantiza que solo el Agent Space específico (no cualquier Agent Space) pueda asumir este rol en la cuenta secundaria.
- También usa `StringEquals` en lugar de `ArnLike` para una coincidencia exacta.

---

### 2.3. `aws_iam_role.secondary_account` — Rol IAM de Cuenta Secundaria

```hcl
resource "aws_iam_role" "secondary_account" {
  count    = var.agent_space_arn != "" ? 1 : 0
  provider = aws.service

  name               = "DevOpsAgentRole-SecondaryAccount-TF"
  assume_role_policy = data.aws_iam_policy_document.secondary_account_trust[0].json
  description        = "Secondary account role for DevOps Agent Space cross-account access"

  tags = var.tags
}
```

**Propósito:** Crea un rol IAM en la **cuenta de servicio secundaria** que el Agent Space puede asumir.

- **`provider = aws.service`:** Usa un proveedor de AWS diferente (configurado en `main.tf`) que apunta a la cuenta secundaria.
- **Nombre fijo:** `DevOpsAgentRole-SecondaryAccount-TF` (sin sufijo aleatorio ya que está en una cuenta diferente).
- **Este rol** es el que se referencia en `deploy-devopsagent.tf` como `aws_iam_role.secondary_account[0].arn` en la asociación secundaria.

---

### 2.4. `aws_iam_role_policy_attachment.secondary_account_access` — Política Administrada para Cuenta Secundaria

```hcl
resource "aws_iam_role_policy_attachment" "secondary_account_access" {
  count    = var.agent_space_arn != "" ? 1 : 0
  provider = aws.service

  role       = aws_iam_role.secondary_account[0].name
  policy_arn = "arn:aws:iam::aws:policy/AIDevOpsAgentAccessPolicy"
}
```

**Propósito:** Adjunta la misma política `AIDevOpsAgentAccessPolicy` al rol de la cuenta secundaria, permitiendo al agente monitorear también los recursos en esta cuenta.

---

### 2.5. Política Inline para Resource Explorer en Cuenta Secundaria

```hcl
data "aws_iam_policy_document" "secondary_account_inline" {
  count = var.agent_space_arn != "" ? 1 : 0

  statement {
    sid    = "AllowCreateServiceLinkedRoles"
    effect = "Allow"
    actions = ["iam:CreateServiceLinkedRole"]
    resources = [
      "arn:aws:iam::${var.service_account_id}:role/aws-service-role/resource-explorer-2.amazonaws.com/AWSServiceRoleForResourceExplorer"
    ]
  }
}

resource "aws_iam_role_policy" "secondary_account_inline" {
  count    = var.agent_space_arn != "" ? 1 : 0
  provider = aws.service
  name     = "AllowCreateServiceLinkedRoles"
  role     = aws_iam_role.secondary_account[0].id
  policy   = data.aws_iam_policy_document.secondary_account_inline[0].json
}
```

**Propósito:** Similar al del rol primario, permite crear el service-linked role de Resource Explorer, pero en la **cuenta secundaria** (notar `var.service_account_id` en lugar de `data.aws_caller_identity.current.account_id`).

---

### 2.6. Función Lambda `echo_service` — Servicio de Ejemplo

```hcl
resource "aws_lambda_function" "echo_service" {
  count    = var.agent_space_arn != "" ? 1 : 0
  provider = aws.service

  function_name = "echo-service-tf"
  description   = "Simple echo service that returns the input event"
  runtime       = "nodejs20.x"
  handler       = "index.handler"
  timeout       = 30
  memory_size   = 128

  filename         = data.archive_file.echo_lambda[0].output_path
  source_code_hash = data.archive_file.echo_lambda[0].output_base64sha256

  role = aws_iam_role.echo_service_role[0].arn

  tags = var.tags
}
```

**Propósito:** Despliega una función Lambda simple de "eco" en la cuenta secundaria como un **servicio de ejemplo** que el DevOps Agent puede monitorear.

- **Runtime:** Node.js 20.x
- **Handler:** `index.handler` (archivo JavaScript generado dinámicamente)
- **Timeout:** 30 segundos
- **Memoria:** 128 MB
- **Código:** Se genera a partir de un archivo comprimido creado con `data.archive_file.echo_lambda`

---

### 2.7. `data.archive_file.echo_lambda` — Archivo ZIP del Código Lambda

```hcl
data "archive_file" "echo_lambda" {
  count       = var.agent_space_arn != "" ? 1 : 0
  type        = "zip"
  output_path = "${path.module}/echo-service.zip"

  source {
    content  = <<-JS
exports.handler = async (event) => {
  console.log('Received event:', JSON.stringify(event, null, 2));
  return {
    statusCode: 200,
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      message: 'Echo service response',
      echo: event,
      timestamp: new Date().toISOString()
    })
  };
};
JS
    filename = "index.js"
  }
}
```

**Propósito:** Crea un archivo ZIP con el código JavaScript de la Lambda directamente desde Terraform (sin necesidad de archivos externos).

- **Código:** Una función Lambda simple que recibe un evento y lo devuelve como respuesta (eco) junto con un timestamp.
- **Salida:** `echo-service.zip` en el directorio del módulo.

---

### 2.8. Rol IAM para la Lambda (`echo_service_role`)

```hcl
resource "aws_iam_role" "echo_service_role" {
  count    = var.agent_space_arn != "" ? 1 : 0
  provider = aws.service

  name               = "echo-service-tf-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_trust[0].json
  tags = var.tags
}

data "aws_iam_policy_document" "lambda_trust" {
  count = var.agent_space_arn != "" ? 1 : 0

  statement {
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
    actions = ["sts:AssumeRole"]
  }
}
```

**Propósito:** Crea un rol IAM que la función Lambda puede asumir para ejecutarse.

- **Política de confianza:** Permite al servicio `lambda.amazonaws.com` asumir el rol.
- **Nombre:** `echo-service-tf-role`

---

### 2.9. `aws_iam_role_policy_attachment.echo_service_basic` — Política de Ejecución Básica para Lambda

```hcl
resource "aws_iam_role_policy_attachment" "echo_service_basic" {
  count    = var.agent_space_arn != "" ? 1 : 0
  provider = aws.service

  role       = aws_iam_role.echo_service_role[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}
```

**Propósito:** Adjunta la política administrada `AWSLambdaBasicExecutionRole` al rol de la Lambda, permitiéndole escribir logs en Amazon CloudWatch.

---

## 3. Archivo `terraform.tfvars.example` — Variables de Ejemplo

Este archivo es una **plantilla** que los usuarios copian a `terraform.tfvars` y personalizan antes del despliegue.

### 3.1. `aws_region`

```hcl
aws_region = "us-east-1"
```

**Propósito:** Especifica la región de AWS donde se desplegarán todos los recursos. `us-east-1` (Norte de Virginia) es el valor por defecto.

---

### 3.2. `name_postfix` (Opcional)

```hcl
# name_postfix = "v2"
```

**Propósito:** Sufijo personalizado para los nombres de los roles IAM. Reemplaza el sufijo aleatorio generado automáticamente.

- **¿Cuándo usarlo?** Cuando necesitas nombres de roles predecibles y consistentes, por ejemplo en entornos de CI/CD o cuando otros sistemas referencian estos roles por nombre.

---

### 3.3. `agent_space_name` y `agent_space_description`

```hcl
agent_space_name        = "MyCompanyAgentSpace"
agent_space_description = "DevOps Agent Space for monitoring production workloads"
```

**Propósito:** Configuran el nombre y la descripción del Agent Space que se creará.

- **`agent_space_name`**: Nombre visible del espacio del agente en la consola de AWS.
- **`agent_space_description`**: Descripción opcional para identificar el propósito del espacio.

---

### 3.4. `service_account_id` (Opcional — Parte 2)

```hcl
# service_account_id = "123456789012"
```

**Propósito:** ID de la cuenta AWS secundaria para monitoreo cross-account.

- **Cuando está comentado/vacío:** Solo se despliega la Parte 1 (monitoreo de cuenta única).
- **Cuando tiene un valor:** Activa los recursos de la Parte 2 (rol cross-account, Lambda de ejemplo).

---

### 3.5. `agent_space_arn` (Opcional — Parte 2)

```hcl
# agent_space_arn = "arn:aws:aidevops:us-east-1:<MONITORING_ACCOUNT_ID>:agentspace/<SPACE_ID>"
```

**Propósito:** ARN del Agent Space creado en la Parte 1. Es necesario para configurar la relación de confianza entre cuentas.

- **¿Cómo obtenerlo?** Es una salida (`output`) del despliegue inicial de la Parte 1.
- **Formato:** `arn:aws:aidevops:<region>:<cuenta_monitoreo>:agentspace/<id_del_espacio>`
- **Ambas variables** (`service_account_id` y `agent_space_arn`) deben estar configuradas para que se activen los recursos de la Parte 2.

---

### 3.6. `tags`

```hcl
tags = {
  Environment = "production"
  Project     = "aws-devops-agent"
  Owner       = "devops-team"
  CostCenter  = "engineering"
}
```

**Propósito:** Etiquetas (tags) que se aplicarán a **todos** los recursos creados por Terraform.

- **Recomendación:** Personalizar según las políticas de etiquetado de la organización.
- **Beneficio:** Facilita la asignación de costos, la identificación de recursos y la gestión de inventario.

---

## Resumen de la Arquitectura Completa

```
┌─────────────────────────────────────────────────────────────────┐
│                    CUENTA DE MONITOREO (Principal)              │
│                                                                 │
│  ┌─────────────────┐    ┌──────────────────────────────┐       │
│  │  iam.tf          │    │  deploy-devopsagent.tf       │       │
│  │                  │    │                              │       │
│  │ Rol: AgentSpace  │───►│ Agent Space ◄─── Rol: Op.   │       │
│  │ Rol: Operator    │    │ Asociación: AWS (monitor)   │       │
│  └─────────────────┘    └──────────────────────────────┘       │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
                            │
                            │ (Confianza entre cuentas)
                            ▼
┌─────────────────────────────────────────────────────────────────┐
│                    CUENTA DE SERVICIO (Secundaria)               │
│                                                                 │
│  ┌──────────────────────────────────────────────────────┐       │
│  │  serviceaccount.tf                                    │       │
│  │                                                       │       │
│  │ Rol: SecondaryAccount (asumido por Agent Space)       │       │
│  │ Lambda: echo-service-tf (servicio de ejemplo)         │       │
│  │ Rol Lambda: echo-service-tf-role                      │       │
│  └──────────────────────────────────────────────────────┘       │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

## Dependencias entre Archivos

| Archivo | Depende de | Razón |
|---------|-----------|-------|
| `iam.tf` | `variables.tf` (var.name_postfix, var.tags) | Variables de configuración |
| `deploy-devopsagent.tf` | `iam.tf` (roles IAM) | Necesita los ARN de los roles |
| `serviceaccount.tf` | `var.agent_space_arn` (output de deploy-devopsagent.tf) | Necesita el ARN del Agent Space |
| `terraform.tfvars` | `terraform.tfvars.example` (plantilla) | Copia del archivo de ejemplo |