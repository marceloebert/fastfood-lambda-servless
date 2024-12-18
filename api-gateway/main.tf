terraform {
  backend "s3" {
    bucket = "lambda-fastfood-tf-state"
    key    = "terraform.tfstate"
    region = "us-east-1"
  }
}

provider "aws" {
  region = var.region
}

# Data Resource para Lambda Function existente
data "aws_lambda_function" "custom_authorizer" {
  function_name = var.lambda_function_name
}

# API Gateway
resource "aws_api_gateway_rest_api" "fastfood_api" {
  name = "FastFoodAPI"
}

# Custom Authorizer
resource "aws_api_gateway_authorizer" "custom_authorizer" {
  name                             = "CustomAuthorizer"
  rest_api_id                      = aws_api_gateway_rest_api.fastfood_api.id
  authorizer_uri                   = "arn:aws:apigateway:${var.region}:lambda:path/2015-03-31/functions/${data.aws_lambda_function.custom_authorizer.arn}/invocations"
  authorizer_result_ttl_in_seconds = 300
  type                             = "REQUEST"
}

# Proxy Integration (Protegido)
resource "aws_api_gateway_resource" "proxy" {
  rest_api_id = aws_api_gateway_rest_api.fastfood_api.id
  parent_id   = aws_api_gateway_rest_api.fastfood_api.root_resource_id
  path_part   = "{proxy+}"
}

resource "aws_api_gateway_method" "proxy_method" {
  rest_api_id   = aws_api_gateway_rest_api.fastfood_api.id
  resource_id   = aws_api_gateway_resource.proxy.id
  http_method   = "ANY"
  authorization = "CUSTOM"
  authorizer_id = aws_api_gateway_authorizer.custom_authorizer.id

  request_parameters = {
    "method.request.path.proxy" = true
  }
}

resource "aws_api_gateway_integration" "proxy_integration" {
  rest_api_id             = aws_api_gateway_rest_api.fastfood_api.id
  resource_id             = aws_api_gateway_resource.proxy.id
  http_method             = aws_api_gateway_method.proxy_method.http_method
  integration_http_method = "ANY"
  uri                     = "${var.eks_service_endpoint}/{proxy}"
  type                    = "HTTP_PROXY"

  request_parameters = {
    "integration.request.path.proxy" = "method.request.path.proxy"
  }

  passthrough_behavior = "WHEN_NO_MATCH"
}

# Rota Pública: /public/{proxy+}
resource "aws_api_gateway_resource" "public_proxy" {
  rest_api_id = aws_api_gateway_rest_api.fastfood_api.id
  parent_id   = aws_api_gateway_rest_api.fastfood_api.root_resource_id
  path_part   = "public"
}

resource "aws_api_gateway_resource" "public_proxy_child" {
  rest_api_id = aws_api_gateway_rest_api.fastfood_api.id
  parent_id   = aws_api_gateway_resource.public_proxy.id
  path_part   = "{proxy+}"
}

resource "aws_api_gateway_method" "public_proxy_method" {
  rest_api_id   = aws_api_gateway_rest_api.fastfood_api.id
  resource_id   = aws_api_gateway_resource.public_proxy_child.id
  http_method   = "ANY"
  authorization = "NONE" # Sem autorização

  request_parameters = {
    "method.request.path.proxy" = true
  }
}

resource "aws_api_gateway_integration" "public_proxy_integration" {
  rest_api_id             = aws_api_gateway_rest_api.fastfood_api.id
  resource_id             = aws_api_gateway_resource.public_proxy_child.id
  http_method             = aws_api_gateway_method.public_proxy_method.http_method
  integration_http_method = "ANY"
  uri                     = "${var.eks_service_endpoint}/{proxy}"
  type                    = "HTTP_PROXY"

  request_parameters = {
    "integration.request.path.proxy" = "method.request.path.proxy"
  }

  passthrough_behavior = "WHEN_NO_MATCH"
}

# Deployment
resource "aws_api_gateway_deployment" "api_deployment" {
  rest_api_id = aws_api_gateway_rest_api.fastfood_api.id
  depends_on  = [
    aws_api_gateway_method.proxy_method,
    aws_api_gateway_method.public_proxy_method
  ]
}

# Stage
resource "aws_api_gateway_stage" "prod_stage" {
  deployment_id = aws_api_gateway_deployment.api_deployment.id
  rest_api_id   = aws_api_gateway_rest_api.fastfood_api.id
  stage_name    = "prod"
}

# Lambda Permission for Custom Authorizer
resource "aws_lambda_permission" "allow_api_gateway" {
  statement_id  = "AllowAPIGatewayInvoke-${var.lambda_function_name}-${aws_api_gateway_rest_api.fastfood_api.id}"
  action        = "lambda:InvokeFunction"
  function_name = data.aws_lambda_function.custom_authorizer.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "arn:aws:execute-api:${var.region}:${var.account_id}:${aws_api_gateway_rest_api.fastfood_api.id}/*"
}
