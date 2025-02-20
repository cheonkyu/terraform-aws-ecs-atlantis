provider "aws" {
  region = local.region
}

provider "github" {
  token = var.github_token
  owner = var.github_owner
}

data "aws_route53_zone" "this" {
  name = var.domain
}

data "aws_availability_zones" "available" {}

locals {
  region = "ap-northeast-2"
  name   = basename(path.cwd)

  vpc_cidr = "10.0.0.0/16"
  azs      = slice(data.aws_availability_zones.available.names, 0, 3)

  tags = {
    Name      = local.name
    Terraform = true
  }
}

##############################################################
# Atlantis
##############################################################

module "atlantis" {
  source = "terraform-aws-modules/atlantis/aws"

  name = "atlantis"

  # ECS
  atlantis = {
    environment = [
      {
        name  = "ATLANTIS_GH_USER"
        value = var.atlantis_github_user
      },
      {
        name  = "ATLANTIS_REPO_ALLOWLIST"
        value = join(",", var.atlantis_repo_allowlist)
      },
      {
        name  = "ATLANTIS_ENABLE_DIFF_MARKDOWN_FORMAT"
        value = "true"
      },
      {
        name : "ATLANTIS_REPO_CONFIG_JSON",
        value : jsonencode(yamldecode(file("${path.module}/server-atlantis.yaml"))),
      },
    ]
    secrets = [
      {
        name      = "ATLANTIS_GH_TOKEN"
        valueFrom = try(module.secrets_manager["github-token"].secret_arn, "")
      },
      {
        name      = "ATLANTIS_GH_WEBHOOK_SECRET"
        valueFrom = try(module.secrets_manager["github-webhook-secret"].secret_arn, "")
      },
    ]
  }

  service = {
    task_exec_secret_arns = [for sec in module.secrets_manager : sec.secret_arn]
    # Provide Atlantis permission necessary to create/destroy resources
    task_exec_iam_role_name = "atlantis-20250218131021996800000001"
    # tasks_iam_role_policies = {
    #   AdministratorAccess = "arn:aws:iam::aws:policy/AdministratorAccess"
    # }
  }

  # ALB
  alb = {
    # For example only
    enable_deletion_protection = true
  }

  alb_subnets     = module.vpc.public_subnets
  service_subnets = module.vpc.private_subnets
  vpc_id          = module.vpc.vpc_id

  # ACM
  certificate_domain_name = "${local.name}.${var.domain}"
  route53_zone_id         = data.aws_route53_zone.this.id

  # EFS
  enable_efs = false
  tags       = local.tags
}

module "github_repository_webhooks" {
  source       = "./modules/github-repository-webhook"
  repositories = var.repositories

  webhook_url    = "${module.atlantis.url}/events"
  webhook_secret = random_password.webhook_secret.result
}

################################################################################
# Supporting Resources
################################################################################

resource "random_password" "webhook_secret" {
  length  = 32
  special = false
}

module "secrets_manager" {
  source  = "terraform-aws-modules/secrets-manager/aws"
  version = "~> 1.0"

  for_each = {
    github-token = {
      secret_string = var.github_token
    }
    github-webhook-secret = {
      secret_string = random_password.webhook_secret.result
    }
  }

  # Secret
  name_prefix             = each.key
  recovery_window_in_days = 0 # For example only
  secret_string           = each.value.secret_string

  tags = local.tags
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = local.name
  cidr = local.vpc_cidr

  azs             = local.azs
  private_subnets = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 4, k)]
  public_subnets  = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 8, k + 48)]

  enable_nat_gateway = false
  single_nat_gateway = false

  tags = local.tags
}

module "nat" {
  source = "int128/nat-instance/aws"

  name                        = local.name # "nat-instance-${name}" prefix가 있음
  vpc_id                      = module.vpc.vpc_id
  public_subnet               = module.vpc.public_subnets[0]
  private_subnets_cidr_blocks = module.vpc.private_subnets_cidr_blocks
  private_route_table_ids     = module.vpc.private_route_table_ids
}

resource "aws_eip" "nat" {
  network_interface = module.nat.eni_id
  tags              = local.tags
}
