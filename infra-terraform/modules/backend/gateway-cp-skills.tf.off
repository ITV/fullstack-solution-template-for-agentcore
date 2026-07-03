# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

# =============================================================================
# AgentCore Gateway
# Maps to: backend-stack.ts createAgentCoreGateway()
# =============================================================================

# -----------------------------------------------------------------------------
# CloudWatch Log Group for Lambda
# -----------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "cp_skills_gateway" {
  name              = "/aws/lambda/${var.stack_name_base}-cp-skills-gateway"
  retention_in_days = local.log_retention_days

}

# -----------------------------------------------------------------------------
# IAM Role for Lambda Function
# -----------------------------------------------------------------------------

data "aws_iam_policy_document" "cp_skills_gateway_lambda_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "cp_skills_gateway_lambda" {
  name               = "${var.stack_name_base}-cp-skills-gateway-lambda-role"
  assume_role_policy = data.aws_iam_policy_document.cp_skills_gateway_lambda_assume_role.json
  description        = "Execution role for CP Skills Gateway Lambda"

}

data "aws_iam_policy_document" "cp_skills_gateway_lambda_policy" {
  statement {
    effect = "Allow"
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    resources = ["${aws_cloudwatch_log_group.cp_skills_gateway.arn}:*"]
  }
}

resource "aws_iam_role_policy" "cp_skills_gateway_lambda" {
  name   = "${var.stack_name_base}-cp-skills-gateway-lambda-policy"
  role   = aws_iam_role.cp_skills_gateway_lambda.id
  policy = data.aws_iam_policy_document.cp_skills_gateway_lambda_policy.json
}

# -----------------------------------------------------------------------------
# Lambda Function for CP Skills Gateway
# -----------------------------------------------------------------------------

locals {
  skills_gateway_lambda_zip_path = "/Users/TomHayn/hackdays/summer-06/cp-context-catalogue/lambda/cp-skills-gateway/cp-skills-gateway.zip"
}

# data "archive_file" "tool_lambda" {
#   type        = "zip"
#   source_dir  = local.skills_gateway_lambda_source_path
#   output_path = "${path.module}/artifacts/gateway_lambda.zip"
#   excludes    = ["tool_spec.json", "__pycache__", "*.pyc"]
# }


resource "aws_lambda_function" "cp_skills_gateway" {
  function_name = "${var.stack_name_base}-cp-skills-gateway"
  role          = aws_iam_role.cp_skills_gateway_lambda.arn
  handler       = "handler.lambda_handler"
  runtime       = "python3.13"
  timeout       = 30

  filename         = local.skills_gateway_lambda_zip_path
  source_code_hash = filebase64sha256(local.skills_gateway_lambda_zip_path)

  depends_on = [aws_cloudwatch_log_group.cp_skills_gateway]

}

# -----------------------------------------------------------------------------
# IAM Role for Gateway
# -----------------------------------------------------------------------------

data "aws_iam_policy_document" "cp_skills_gateway_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["bedrock-agentcore.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "cp_skills_gateway_policy" {
  # Lambda invoke permission
  statement {
    sid    = "LambdaInvoke"
    effect = "Allow"
    actions = [
      "lambda:InvokeFunction"
    ]
    resources = [aws_lambda_function.cp_skills_gateway.arn]
  }

  # Bedrock permissions (region-agnostic)
  statement {
    sid    = "BedrockInvoke"
    effect = "Allow"
    actions = [
      "bedrock:InvokeModel",
      "bedrock:InvokeModelWithResponseStream"
    ]
    resources = [
      "arn:aws:bedrock:*::foundation-model/*",
      "arn:aws:bedrock:*:${local.account_id}:inference-profile/*"
    ]
  }

  # SSM parameter access
  statement {
    sid    = "SSMAccess"
    effect = "Allow"
    actions = [
      "ssm:GetParameter",
      "ssm:GetParameters"
    ]
    resources = ["arn:aws:ssm:${local.region}:${local.account_id}:parameter/${var.stack_name_base}/*"]
  }

  # Cognito permissions
  statement {
    sid    = "CognitoAccess"
    effect = "Allow"
    actions = [
      "cognito-idp:DescribeUserPoolClient",
      "cognito-idp:InitiateAuth"
    ]
    resources = [var.user_pool_arn]
  }

  # CloudWatch Logs
  statement {
    sid    = "CloudWatchLogs"
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    resources = ["arn:aws:logs:${local.region}:${local.account_id}:log-group:/aws/bedrock-agentcore/*"]
  }
}

resource "aws_iam_role_policy" "cp_skills_gateway" {
  name   = "${var.stack_name_base}-cp-skillsgateway-policy"
  role   = aws_iam_role.gateway.id
  policy = data.aws_iam_policy_document.cp_skills_gateway_policy.json
}

# # --- Lambda Function URL, IAM-authenticated (payload format 2.0, which
# #     handler.http_handler already expects: rawPath, requestContext.http.method) ---

# resource "aws_lambda_function_url" "cp_skills_gateway" {
#   function_name      = aws_lambda_function.cp_skills_gateway.function_name
#   authorization_type = "AWS_IAM"
# }

# # Allow the gateway's SigV4-signed calls in. Gateway signs as its own
# # execution role, invoking via the "bedrock-agentcore" service principal.
# resource "aws_lambda_permission" "allow_gateway_invoke_url" {
#   statement_id           = "AllowBedrockAgentCoreInvokeFunctionUrl"
#   action                 = "lambda:InvokeFunctionUrl"
#   function_name          = aws_lambda_function.cp_skills_gateway.function_name
#   principal              = "bedrock-agentcore.amazonaws.com"
#   function_url_auth_type = "AWS_IAM"
#   source_account         = data.aws_caller_identity.current.account_id
# }

# data "aws_caller_identity" "current" {}

# -----------------------------------------------------------------------------
# AgentCore Gateway Target
# -----------------------------------------------------------------------------

resource "aws_bedrockagentcore_gateway_target" "cp_skills_list" {
  name               = "cp-skills-list"
  gateway_identifier = aws_bedrockagentcore_gateway.main.gateway_id
  description        = "List available ITV Common Platform skills"

  credential_provider_configuration {
    gateway_iam_role {}
  }

  target_configuration {
    mcp {
      lambda {
        lambda_arn = aws_lambda_function.cp_skills_gateway.arn

        tool_schema {
          inline_payload {
            name        = "list_skills"
            description = "List available ITV Common Platform skills (name, source package, description) from the cp-context-catalogue APM packages. Call this first to discover which skill covers a task before calling get_skill."

            input_schema {
              type        = "object"
              description = "Optional filter for the skill catalogue listing."

              property {
                name        = "package"
                type        = "string"
                description = "Restrict results to one source package, e.g. 'cpv3-components'."
              }
            }

            output_schema {
              type = "object"

              property {
                name        = "skills"
                type        = "array"
                description = "One entry per matching skill."

                items {
                  type = "object"

                  property {
                    name     = "name"
                    type     = "string"
                    required = true
                  }
                  property {
                    name     = "package"
                    type     = "string"
                    required = true
                  }
                  property {
                    name     = "description"
                    type     = "string"
                    required = true
                  }
                }
              }
            }
          }
        }
      }
    }
  }
  depends_on = [aws_bedrockagentcore_gateway.main]
}

resource "aws_bedrockagentcore_gateway_target" "cp_skills_get" {
  name               = "cp-skills-get"
  gateway_identifier = aws_bedrockagentcore_gateway.main.gateway_id
  description        = "Fetch full instructions for one ITV Common Platform skill"

  credential_provider_configuration {
    gateway_iam_role {}
  }

  target_configuration {
    mcp {
      lambda {
        lambda_arn = aws_lambda_function.cp_skills_gateway.arn

        tool_schema {
          inline_payload {
            name        = "get_skill"
            description = "Fetch the full instructions (SKILL.md body and any bundled reference files) for one named ITV Common Platform skill. Call list_skills first to find the right name."

            input_schema {
              type = "object"

              property {
                name        = "name"
                type        = "string"
                description = "The skill's name, as returned by list_skills."
                required    = true
              }

              property {
                name        = "package"
                type        = "string"
                description = "Optional: restrict the lookup to this source package."
              }
            }

            output_schema {
              type = "object"

              property {
                name     = "name"
                type     = "string"
                required = true
              }
              property {
                name = "package"
                type = "string"
              }
              property {
                name = "description"
                type = "string"
              }
              property {
                name = "argument_hint"
                type = "string"
              }
              property {
                name        = "body"
                type        = "string"
                description = "The skill's full markdown instructions."
                required    = true
              }
              property {
                name        = "references"
                type        = "object"
                description = "Bundled reference files, keyed by filename, with markdown content as values."
              }
            }
          }
        }
      }
    }
  }
  depends_on = [aws_bedrockagentcore_gateway.main]
}

