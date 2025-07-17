provider "aws" {
  region = var.region
}

resource "aws_s3_bucket" "static_site" {
  bucket = var.bucket_name
}

resource "aws_s3_bucket_website_configuration" "static_site_config" {
  bucket = aws_s3_bucket.static_site.bucket

  index_document {
    suffix = "index.html"
  }
}

resource "aws_s3_bucket_public_access_block" "static_site_block" {
  bucket = aws_s3_bucket.static_site.id

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

resource "aws_s3_bucket_policy" "static_site_policy" {
  bucket = aws_s3_bucket.static_site.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Principal = "*",
        Action = ["s3:GetObject"],
        Resource = "${aws_s3_bucket.static_site.arn}/*"
      }
    ]
  })
}

resource "aws_iam_role" "codebuild_service_role" {
  name = "codebuild-service-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Principal = {
          Service = "codebuild.amazonaws.com"
        },
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy" "codebuild_logs_policy" {
  name = "AllowCloudWatchLogs"
  role = aws_iam_role.codebuild_service_role.name

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy" "codebuild_s3_read_policy" {
  name = "AllowS3ReadWriteForBuildArtifacts"
  role = aws_iam_role.codebuild_service_role.name

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "s3:GetObject",
          "s3:PutObject"
        ],
        Resource = ["${aws_s3_bucket.static_site.arn}/*"]
      }
    ]
  })
}

resource "aws_codebuild_project" "static_site_build" {
  name          = "static-site-build"
  service_role  = aws_iam_role.codebuild_service_role.arn
  description   = "Build project for static website"

  artifacts {
    type = "CODEPIPELINE"
  }

  environment {
    compute_type    = "BUILD_GENERAL1_SMALL"
    image           = "aws/codebuild/standard:5.0"
    type            = "LINUX_CONTAINER"
    privileged_mode = false
  }

  source {
    type     = "CODEPIPELINE"
    buildspec = file("buildspec.yml")
  }
}

resource "aws_iam_role" "codepipeline_service_role" {
  name = "codepipeline-service-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Principal = {
          Service = "codepipeline.amazonaws.com"
        },
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy" "codepipeline_s3_write_policy" {
  name = "S3WriteAccessForPipeline"
  role = aws_iam_role.codepipeline_service_role.name

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "s3:GetObject",
          "s3:GetObjectVersion",
          "s3:PutObject"
        ],
        Resource = ["${aws_s3_bucket.static_site.arn}/*"]
      }
    ]
  })
}

resource "aws_iam_role_policy" "codepipeline_codebuild_start_policy" {
  name = "AllowStartBuild"
  role = aws_iam_role.codepipeline_service_role.name

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = ["codebuild:StartBuild"],
        Resource = aws_codebuild_project.static_site_build.arn
      }
    ]
  })
}

resource "aws_iam_role_policy" "codepipeline_codestar_policy" {
  name = "CodeStarConnectionAccess"
  role = aws_iam_role.codepipeline_service_role.name

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = ["codestar-connections:UseConnection"],
        Resource = var.connection_arn
      }
    ]
  })
}

resource "aws_iam_role_policy" "codepipeline_batch_get_builds_policy" {
  name = "AllowBatchGetBuilds"
  role = aws_iam_role.codepipeline_service_role.name

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = ["codebuild:BatchGetBuilds"],
        Resource = aws_codebuild_project.static_site_build.arn
      }
    ]
  })
}

resource "aws_codepipeline" "static_site_pipeline" {
  name     = "static-site-pipeline"
  role_arn = aws_iam_role.codepipeline_service_role.arn

  artifact_store {
    location = aws_s3_bucket.static_site.bucket
    type     = "S3"
  }

  stage {
    name = "Source"

    action {
      name             = "Source"
      category         = "Source"
      owner            = "AWS"
      provider         = "CodeStarSourceConnection"
      version          = "1"
      output_artifacts = ["source_out"]

      configuration = {
        ConnectionArn    = var.connection_arn
        FullRepositoryId = var.repo_name
        BranchName       = var.branch
      }
    }
  }

  stage {
    name = "Build"

    action {
      name             = "Build"
      category         = "Build"
      owner            = "AWS"
      provider         = "CodeBuild"
      input_artifacts  = ["source_out"]
      output_artifacts = ["build_outp"]
      version          = "1"

      configuration = {
        ProjectName = aws_codebuild_project.static_site_build.name
      }
    }
  }

  stage {
    name = "Deploy"

    action {
      name            = "Deploy"
      category        = "Deploy"
      owner           = "AWS"
      provider        = "S3"
      input_artifacts = ["build_outp"]
      version         = "1"

      configuration = {
        BucketName = aws_s3_bucket.static_site.bucket
        Extract    = "true"
      }
    }
  }
}

output "bucket_name" {
  value = aws_s3_bucket.static_site.bucket
}

output "website_url" {
  value = aws_s3_bucket.static_site.website_endpoint
}

