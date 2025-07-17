variable "region" {
  description = "AWS region"
  default     = "us-east-1"
}

variable "bucket_name" {
  description = "Name of the S3 bucket for static website"
  type        = string
}

variable "repo_name" {
  description = "GitHub repo in the format username/repo"
  type        = string
}

variable "branch" {
  description = "Branch to use in the repo"
  type        = string
}

variable "connection_arn" {
  description = "CodeStar Connection ARN"
  type        = string
}

