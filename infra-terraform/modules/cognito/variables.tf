# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

variable "stack_name_base" {
  description = "Base name for all resources."
  type        = string
}

variable "admin_user_email" {
  description = "Email address for the admin user. If provided, creates an admin user."
  type        = string
  default     = null
}

variable "amplify_url" {
  description = "Amplify app URL to add to callback URLs."
  type        = string
  default     = null
}

# =============================================================================
# Existing User Pool (Optional)
# =============================================================================
# When set, the module reuses an existing Cognito User Pool (e.g. one already
# used elsewhere, such as for ALB authentication) instead of creating a new
# one. A new app client for the frontend is still created inside that pool.

variable "existing_user_pool_id" {
  description = "ID of an existing Cognito User Pool to reuse. If null (default), a new user pool is created. The pool's hosted-UI domain is looked up automatically."
  type        = string
  default     = null
}
