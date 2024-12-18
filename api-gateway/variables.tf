variable "region" {
  description = "AWS region"
  default     = "us-east-1"
}

variable "eks_service_endpoint" {
  description = "EKS public endpoint"
  default     = "http://a55d9d72e2eb54d588a9098cff7e2d6f-1311634885.us-east-1.elb.amazonaws.com"
}

variable "lambda_function_name" {
  description = "Custom Authorizer Lambda function name"
  default     = "CustomAuthorizerLambda"
}

variable "account_id" {
  description = "AWS account ID"
  default     = "796677153840"
}