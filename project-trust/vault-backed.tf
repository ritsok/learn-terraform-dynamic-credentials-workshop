resource "aws_iam_user" "secrets_engine" {
  name = "hcp-vault-secrets-engine"
}

resource "aws_iam_access_key" "secrets_engine_credentials" {
  user = aws_iam_user.secrets_engine.name
}

resource "aws_iam_user_policy" "vault_secrets_engine_generate_credentials" {
  user = aws_iam_user.secrets_engine.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "sts:AssumeRole",
        ]
        Effect   = "Allow"
        Resource = "${aws_iam_role.tfc_role.arn}"
      },
    ]
  })
}

resource "aws_iam_role" "tfc_role" {
  name = "tfc-role"

  assume_role_policy = jsonencode(
    {
      Statement = [
        {
          Action    = "sts:AssumeRole"
          Condition = {}
          Effect    = "Allow"
          Principal = {
            AWS = aws_iam_user.secrets_engine.arn
          }
        },
      ]
      Version = "2012-10-17"
    }
  )
}

resource "vault_aws_secret_backend" "aws_secret_backend" {
  namespace = var.vault_namespace
  path      = "aws"

  access_key = aws_iam_access_key.secrets_engine_credentials.id
  secret_key = aws_iam_access_key.secrets_engine_credentials.secret
}

resource "vault_aws_secret_backend_role" "aws_secret_backend_role" {
  backend         = vault_aws_secret_backend.aws_secret_backend.path
  name            = var.aws_secret_backend_role_name
  credential_type = "assumed_role"

  role_arns = [aws_iam_role.tfc_role.arn]
}

resource "vault_jwt_auth_backend" "tfc_jwt" {
  path               = var.jwt_backend_path
  type               = "jwt"
  oidc_discovery_url = "https://${var.tfc_hostname}"
  bound_issuer       = "https://${var.tfc_hostname}"
}

resource "vault_policy" "tfc_policy" {
  name = "tfc-secrets-engine-policy"

  policy = <<EOT
# Allow tokens to query themselves
path "auth/token/lookup-self" {
  capabilities = ["read"]
}

# Allow tokens to renew themselves
path "auth/token/renew-self" {
    capabilities = ["update"]
}

# Allow tokens to revoke themselves
path "auth/token/revoke-self" {
    capabilities = ["update"]
}

# Allow Access to AWS Secrets Engine
path "aws/sts/${var.aws_secret_backend_role_name}" {
  capabilities = [ "read" ]
}
EOT
}

resource "tfe_variable_set" "vault_credentials" {
  name         = "Vault Credentials for trust relationships"
  description  = "Vault Credentials for trust relationships project."
  organization = var.tfc_organization_name
}

resource "tfe_project_variable_set" "vault_credentials" {
  variable_set_id = tfe_variable_set.vault_credentials.id
  project_id = tfe_project.trust_relationships.id
}

resource "tfe_variable" "tfc_vault_addr" {
  key       = "TFC_VAULT_ADDR"
  value     = var.vault_url
  category  = "env"
  sensitive = true
  description = "The address of the Vault instance runs will access."
  variable_set_id = tfe_variable_set.vault_credentials.id
}

resource "tfe_variable" "tfc_aws_mount_path" {
  key      = "TFC_VAULT_BACKED_AWS_MOUNT_PATH"
  value    = vault_aws_secret_backend.aws_secret_backend.path
  category = "env"
  description = "Path to where the AWS Secrets Engine is mounted in Vault."
  variable_set_id = tfe_variable_set.vault_credentials.id
}

resource "tfe_variable" "tfc_vault_token" {
  key      = "VAULT_TOKEN"
  value    = var.vault_token
  category = "env"
  sensitive = true
  description = "Vault token."
  variable_set_id = tfe_variable_set.vault_credentials.id
}
