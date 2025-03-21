provider "aws" {
  region = "us-east-1"
  profile = "vsjewel"
}

resource "aws_iam_role" "eks_cluster_role" {
  name = "eks-cluster-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Service = "eks.amazonaws.com" }
        Action    = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  role       = aws_iam_role.eks_cluster_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

resource "aws_eks_cluster" "dev" {
  name     = "dev"
  role_arn = aws_iam_role.eks_cluster_role.arn
  version  = "1.28"

  vpc_config {
    subnet_ids = [
      "subnet-0091026ca11deddb8",
      "subnet-07d5e2990792a7122"
    ]
    endpoint_private_access = true
    endpoint_public_access  = true
  }

  enabled_cluster_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
}

resource "aws_iam_role" "node_role" {
  name = "eks-node-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Service = "ec2.amazonaws.com" }
        Action    = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "node_policies" {
  count      = 3
  role       = aws_iam_role.node_role.name
  policy_arn = [
    "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy",
    "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy",
    "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  ][count.index]
}

resource "aws_eks_node_group" "cluster_worker" {
  cluster_name    = aws_eks_cluster.dev.name
  node_group_name = "cluster-worker"
  node_role_arn   = aws_iam_role.node_role.arn
  subnet_ids      = ["subnet-0091026ca11deddb8",
      "subnet-07d5e2990792a7122"]

  instance_types = ["t3.medium"]

  scaling_config {
    desired_size = 2
    max_size     = 4
    min_size     = 2
  }

  labels = {
    arch      = "x86"
    disk      = "none"
    noderole  = "spark"
  }

  tags = {
    "k8s.io/cluster-autoscaler/enabled" = "true"
    "k8s.io/cluster-autoscaler/experiments" = "owned"
  }
}

resource "aws_iam_policy" "s3_access_policy" {
  name        = "S3AccessPolicy"
  description = "Policy to allow Spark nodes to access S3"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect   = "Allow",
        Action   = [
          "s3:ListBucket",
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject"
        ],
        Resource = [
          "arn:aws:s3:::dataplatfrom-demo-bucket",
          "arn:aws:s3:::dataplatfrom-demo-bucket/*"
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "s3_access_attachment" {
  role       = aws_iam_role.node_role.name
  policy_arn = aws_iam_policy.s3_access_policy.arn
}


resource "aws_iam_policy" "s3_dynamodb_glue_access_policy" {
  name        = "S3DynamoDBGlueAccessPolicy"
  description = "Policy to allow Spark nodes to access S3, DynamoDB, and Glue for Iceberg Glue Catalog"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect   = "Allow",
        Action   = [
          "s3:ListBucket",
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject"
        ],
        Resource = [
          "arn:aws:s3:::dataplatfrom-demo-bucket",
          "arn:aws:s3:::dataplatfrom-demo-bucket/*"
        ]
      },
      {
        Effect   = "Allow",
        Action   = [
          "dynamodb:DescribeTable",
          "dynamodb:PutItem",
          "dynamodb:GetItem",
          "dynamodb:DeleteItem",
          "dynamodb:UpdateItem"
        ],
        Resource = "arn:aws:dynamodb:*:*:table/hive_glue_catalog_locks"
      },
      {
        Effect   = "Allow",
        Action   = [
          "glue:CreateDatabase",
          "glue:DeleteDatabase",
          "glue:GetDatabase",
          "glue:UpdateDatabase",
          "glue:CreateTable",
          "glue:DeleteTable",
          "glue:GetTable",
          "glue:UpdateTable",
          "glue:GetPartition",
          "glue:CreatePartition",
          "glue:DeletePartition"
        ],
        Resource = "arn:aws:glue:*:*:*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "s3_dynamodb_glue_access_attachment" {
  role       = aws_iam_role.node_role.name
  policy_arn = aws_iam_policy.s3_dynamodb_glue_access_policy.arn
}
