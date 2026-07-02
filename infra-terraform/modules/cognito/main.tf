# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

# =============================================================================
# Data Sources
# =============================================================================

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# =============================================================================
# Local Values
# =============================================================================

locals {
  account_id = data.aws_caller_identity.current.account_id
  region     = data.aws_region.current.id

  # Reuse an existing pool if provided, otherwise create a new one
  use_existing_pool = var.existing_user_pool_id != null

  # Cognito domain prefix (must be globally unique and lowercase)
  domain_prefix = "${lower(replace(var.stack_name_base, "_", "-"))}-${local.account_id}-${local.region}"

  # Callback URLs (hardcoded to match CDK cognito-stack.ts defaults)
  default_callback_urls = ["http://localhost:3000", "https://localhost:3000"]

  # Combine callback URLs with Amplify URL if provided
  all_callback_urls = var.amplify_url != null ? concat(local.default_callback_urls, [var.amplify_url]) : local.default_callback_urls

  # Password minimum length (hardcoded to match CDK cognito-stack.ts)
  password_minimum_length = 8

  # User invitation email template
  invitation_email_subject = "Welcome to ${var.stack_name_base}!"
  invitation_email_body    = <<-EOF
<p>Hello {username},</p>
<p>Welcome to ${var.stack_name_base}! Your username is <strong>{username}</strong> and your temporary password is: <strong>{####}</strong></p>
<p>Please use this temporary password to log in and set your permanent password.</p>
<p>The CloudFront URL to your application is stored as an output in the "${var.stack_name_base}" stack, and will be printed to your terminal once the deployment process completes.</p>
<p>Thanks,</p>
<p>Fullstack AgentCore Solution Template Team</p>
EOF
}

# =============================================================================
# Cognito User Pool
# =============================================================================
# Main user pool for authentication with password policy and invitation templates

resource "aws_cognito_user_pool" "main" {
  count = local.use_existing_pool ? 0 : 1

  name = "${var.stack_name_base}-user-pool"

  # Admin-only user creation (self sign-up disabled)
  admin_create_user_config {
    allow_admin_create_user_only = true

    # User invitation email template
    invite_message_template {
      email_subject = local.invitation_email_subject
      email_message = local.invitation_email_body
      sms_message   = "Your username is {username} and temporary password is {####}"
    }
  }

  # Sign-in with email
  username_attributes = ["email"]

  # Auto-verify email
  auto_verified_attributes = ["email"]

  # Account recovery via email only
  account_recovery_setting {
    recovery_mechanism {
      name     = "verified_email"
      priority = 1
    }
  }

  # Password policy
  password_policy {
    minimum_length                   = local.password_minimum_length
    require_lowercase                = true
    require_uppercase                = true
    require_numbers                  = true
    require_symbols                  = true
    temporary_password_validity_days = 7
  }

  # Email attribute (required and immutable)
  schema {
    name                     = "email"
    attribute_data_type      = "String"
    required                 = true
    mutable                  = false
    developer_only_attribute = false

    string_attribute_constraints {
      min_length = 0
      max_length = 2048
    }
  }

  # Email configuration
  email_configuration {
    email_sending_account = "COGNITO_DEFAULT"
  }

  # Allow deletion (no protection)
  deletion_protection = "INACTIVE"
}

# =============================================================================
# Existing User Pool Lookup (when existing_user_pool_id is set)
# =============================================================================

data "aws_cognito_user_pool" "existing" {
  count = local.use_existing_pool ? 1 : 0

  user_pool_id = var.existing_user_pool_id
}

locals {
  # Effective pool identity, regardless of whether it was created here or reused
  effective_user_pool_id  = local.use_existing_pool ? var.existing_user_pool_id : aws_cognito_user_pool.main[0].id
  effective_user_pool_arn = local.use_existing_pool ? data.aws_cognito_user_pool.existing[0].arn : aws_cognito_user_pool.main[0].arn
  effective_domain        = local.use_existing_pool ? data.aws_cognito_user_pool.existing[0].domain : aws_cognito_user_pool_domain.main[0].domain
}

# =============================================================================
# Cognito User Pool Domain
# =============================================================================
# Domain for hosted UI with managed login V2.
# Skipped when reusing an existing pool — it already has a domain.

resource "aws_cognito_user_pool_domain" "main" {
  count = local.use_existing_pool ? 0 : 1

  domain       = local.domain_prefix
  user_pool_id = aws_cognito_user_pool.main[0].id
}

# =============================================================================
# Cognito Managed Login Branding (V2)
# =============================================================================
# Required for the v2 managed login to display properly.
# Skipped when reusing an existing pool to avoid touching its branding.

resource "aws_cognito_managed_login_branding" "main" {
  count = local.use_existing_pool ? 0 : 1

  user_pool_id = aws_cognito_user_pool.main[0].id
  client_id    = aws_cognito_user_pool_client.web.id

  # Use Cognito's default styles
  use_cognito_provided_values = true

  depends_on = [aws_cognito_user_pool_domain.main]
}

# =============================================================================
# Cognito User Pool Client - Web (Frontend)
# =============================================================================
# OAuth client for frontend application

resource "aws_cognito_user_pool_client" "web" {
  name         = "${var.stack_name_base}-client"
  user_pool_id = local.effective_user_pool_id

  # No secret for public client
  generate_secret = false

  # Auth flows
  explicit_auth_flows = [
    "ALLOW_USER_PASSWORD_AUTH",
    "ALLOW_USER_SRP_AUTH",
    "ALLOW_REFRESH_TOKEN_AUTH"
  ]

  # OAuth configuration
  allowed_oauth_flows                  = ["code"]
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_scopes                 = ["openid", "email", "profile"]

  # Callback and logout URLs
  callback_urls = local.all_callback_urls
  logout_urls   = local.all_callback_urls

  # Supported identity providers
  supported_identity_providers = ["COGNITO"]

  # Prevent user existence errors
  prevent_user_existence_errors = "ENABLED"

  # Token validity
  access_token_validity  = 1
  id_token_validity      = 1
  refresh_token_validity = 30

  token_validity_units {
    access_token  = "hours"
    id_token      = "hours"
    refresh_token = "days"
  }
}

# =============================================================================
# Cognito Admin User (Conditional)
# =============================================================================
# Creates admin user if email is provided

resource "aws_cognito_user" "admin" {
  count = var.admin_user_email != null ? 1 : 0

  user_pool_id = local.effective_user_pool_id
  username     = var.admin_user_email

  attributes = {
    email          = var.admin_user_email
    email_verified = true
  }

  # Send invitation email with temporary password
  desired_delivery_mediums = ["EMAIL"]
}
