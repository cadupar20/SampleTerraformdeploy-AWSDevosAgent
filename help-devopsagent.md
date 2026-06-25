# Explicación Detallada de `deploy-devopsagent.tf`

Este archivo define los recursos necesarios para desplegar un **AWS DevOps Agent** —un servicio administrado de AWS para monitoreo y operaciones de DevOps— usando el **proveedor CloudFormation Control (AWSCC)** de Terraform.

---

## 1. Recurso `time_sleep.wait_for_iam_propagation`

```hcl
resource "time_sleep" "wait_for_iam_propagation" {
  depends_on = [
    aws_iam_role.devops_agentspace,
    aws_iam_role_policy_attachment.devops_agentspace_access,
    aws_iam_role_policy.devops_agentspace_inline,
    aws_iam_role.devops_operator,
    aws_iam_role_policy_attachment.devops_operator_access
  ]

  create_duration = "30s"
}
```

**Propósito:** AWS IAM (Identity and Access Management) tiene un [retraso de propagación](https://docs.aws.amazon.com/IAM/latest/UserGuide/troubleshoot_general.html#troubleshoot_general_eventual-consistency) eventualmente consistente. Después de crear roles y políticas, puede tomar algunos segundos antes de que estén disponibles para ser usados por otros servicios.

- **`depends_on`**: Espera explícitamente a que los 5 recursos IAM (roles, adjuntos de políticas, políticas inline) estén creados.
- **`create_duration = "30s"`**: Introduce una pausa de 30 segundos después de crear los recursos IAM antes de continuar.

**Por qué es necesario:** Sin esta pausa, el siguiente recurso (`awscc_devopsagent_agent_space`) podría fallar porque el rol IAM aún no es visible/usable por el servicio de DevOps Agent.

---

## 2. Recurso `awscc_devopsagent_agent_space.main`

```hcl
resource "awscc_devopsagent_agent_space" "main" {
  name        = var.agent_space_name
  description = var.agent_space_description

  operator_app = {
    iam = {
      operator_app_role_arn = aws_iam_role.devops_operator.arn
    }
  }

  depends_on = [
    time_sleep.wait_for_iam_propagation
  ]
}
```

**Propósito:** Crea el **Agent Space** (Espacio del Agente), que es el contenedor lógico donde vive el DevOps Agent. Es el recurso principal de este archivo.

- **`name` y `description`**: Variables de Terraform (`var.agent_space_name`, `var.agent_space_description`) para nombrar y describir el espacio.
- **`operator_app.iam.operator_app_role_arn`**: Asocia el rol IAM `devops_operator` a la aplicación operadora del Agent Space. Este es el rol que usará la aplicación para interactuar con los recursos de AWS.
- **`depends_on`**: Espera que el `time_sleep` termine (es decir, que hayan pasado los 30s después de la creación de los roles IAM).

**Analogía:** Piensa en el Agent Space como una "cuenta de proyecto" dentro del servicio DevOps Agent, donde configuras qué operadores pueden acceder y a qué cuentas monitorear.

---

## 3. Recurso `awscc_devopsagent_association.primary_aws_account`

```hcl
resource "awscc_devopsagent_association" "primary_aws_account" {
  agent_space_id = awscc_devopsagent_agent_space.main.id
  service_id     = "aws"

  configuration = {
    aws = {
      assumable_role_arn = aws_iam_role.devops_agentspace.arn
      account_id         = data.aws_caller_identity.current.account_id
      account_type       = "monitor"
      resources          = []
    }
  }

  depends_on = [
    awscc_devopsagent_agent_space.main
  ]
}
```

**Propósito:** **Asocia la cuenta AWS actual** (donde se ejecuta Terraform) al Agent Space como una cuenta a monitorear. Esto le da permiso al DevOps Agent para observar recursos en esta cuenta.

- **`agent_space_id`**: Referencia al Agent Space creado arriba.
- **`service_id = "aws"`**: Indica que la asociación es con el servicio de AWS (podrían ser otros servicios como GitHub, etc.).
- **`configuration.aws`**: Bloque de configuración para AWS:
  - **`assumable_role_arn`**: El ARN del rol `devops_agentspace` que el servicio podrá asumir para acceder a la cuenta.
  - **`account_id`**: Obtiene dinámicamente el ID de la cuenta actual usando `data.aws_caller_identity.current`.
  - **`account_type = "monitor"`**: Define la cuenta como de tipo **monitor** (la cuenta que será observada/monitoreada).
  - **`resources = []`**: Lista vacía significa que el agente puede monitorear **todos** los recursos (no hay restricción por ARN).

**Flujo:** El DevOps Agent asumirá el rol `devops_agentspace` en esta cuenta para recolectar métricas, eventos, y realizar tareas de monitoreo.

---

## 4. Recurso `awscc_devopsagent_association.secondary_aws_account` (opcional)

```hcl
resource "awscc_devopsagent_association" "secondary_aws_account" {
  count = var.service_account_id != "" && var.agent_space_arn != "" ? 1 : 0

  agent_space_id = awscc_devopsagent_agent_space.main.id
  service_id     = "aws"

  configuration = {
    source_aws = {
      assumable_role_arn = aws_iam_role.secondary_account[0].arn
      account_id         = var.service_account_id
      account_type       = "source"
    }
  }

  depends_on = [
    awscc_devopsagent_association.primary_aws_account
  ]
}
```

**Propósito:** **Opcionalmente** asocia una **cuenta secundaria** (cross-account) para monitoreo desde otra cuenta AWS. Esto permite al DevOps Agent observar recursos en múltiples cuentas.

- **`count`**: Usa la [meta-argumento `count`](https://developer.hashicorp.com/terraform/language/meta-arguments/count) condicional:
  - Solo se crea si: `var.service_account_id != ""` (se proporcionó un ID de cuenta) **Y** `var.agent_space_arn != ""` (se proporcionó un ARN del Agent Space, probablemente de una salida de otro stack).
  - Si no se cumplen ambas condiciones, `count = 0` y el recurso no se crea.

- **`configuration.source_aws`**: Similar al bloque `aws` pero para una cuenta **source** (origen):
  - **`assumable_role_arn`**: Referencia al rol `aws_iam_role.secondary_account[0].arn` — un rol creado en la cuenta secundaria que el agente puede asumir. Usa `[0]` porque con `count` se accede por índice.
  - **`account_id`**: El ID de la cuenta secundaria (variable).
  - **`account_type = "source"`**: Define la cuenta como **source** (cuenta de origen/origen de datos), en contraposición a "monitor".

- **`depends_on`**: Se asegura de que la asociación primaria ya exista antes de crear la secundaria (orden lógico de operaciones).

**Caso de uso típico:** Monitoreo multi-cuenta donde tienes una cuenta central de observabilidad y varias cuentas de aplicación/origen que deseas monitorear.

---

## Resumen del Flujo Completo

```
  1. Crear Roles IAM
       │
       ▼
  2. Esperar 30s (propagación IAM)
       │
       ▼
  3. Crear Agent Space
       │
       ▼
  4. Asociar Cuenta Primaria (monitor)
       │
       ▼
  5. (Opcional) Asociar Cuenta Secundaria (source)
```

## Arquitectura General

```
┌─────────────────────────────────────────────────────┐
│                    Cuenta AWS Actual                 │
│                                                      │
│  ┌────────────────────────────────────────────┐     │
│  │         Agent Space (devopsagent)          │     │
│  │                                            │     │
│  │  Rol: devops_operator ──► App Operator    │     │
│  │  Rol: devops_agentspace ──► Monitoreo     │     │
│  └────────────────────────────────────────────┘     │
│                          │                           │
│                          ▼                           │
│              Monitorea recursos locales              │
│                                                      │
│  ┌────────────────────────────────────────────┐     │
│  │      Cuenta Secundaria (opcional)          │     │
│  │  Rol: secondary_account ──► Cross-account  │     │
│  └────────────────────────────────────────────┘     │
└─────────────────────────────────────────────────────┘
```

## Dependencias Clave

| Recurso | Depende de | Razón |
|---|---|---|
| `time_sleep` | 5 recursos IAM | Esperar propagación |
| `awscc_devopsagent_agent_space` | `time_sleep` | Roles ya propagados |
| `awscc_devopsagent_association.primary` | `agent_space` | El espacio debe existir |
| `awscc_devopsagent_association.secondary` | `assoc. primary` | Orden lógico |