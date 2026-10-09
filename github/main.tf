terraform {
  required_version = "1.12.6"
  required_providers {
    github = {
      source  = "integrations/github"
      version = "6.13.0"
    }
  }
}

variable "writer_app_id" {
  type = number
}

provider "github" {
  owner = "jellalshadows-idp"
  # token: GITHUB_TOKEN env, minted from the writer App
}

resource "github_team" "spike" {
  name    = "spike-team"
  privacy = "closed"
}

# adrian-da-silva is NOT an org member: this sends an org invitation (pending).
resource "github_team_membership" "invitee" {
  team_id  = github_team.spike.id
  username = "adrian-da-silva"
  role     = "member"
}

resource "github_repository" "spike" {
  name                   = "spike-component"
  visibility             = "public"
  auto_init              = true
  delete_branch_on_merge = true
  vulnerability_alerts   = true
  archive_on_destroy     = false
}

resource "github_team_repository" "spike" {
  team_id    = github_team.spike.id
  repository = github_repository.spike.name
  permission = "maintain"
}

resource "github_repository_ruleset" "main" {
  name        = "main"
  repository  = github_repository.spike.name
  target      = "branch"
  enforcement = "active"

  conditions {
    ref_name {
      include = ["~DEFAULT_BRANCH"]
      exclude = []
    }
  }

  bypass_actors {
    actor_id    = var.writer_app_id
    actor_type  = "Integration"
    bypass_mode = "always"
  }

  rules {
    deletion         = true
    non_fast_forward = true
    pull_request {
      required_approving_review_count = 1
    }
  }
}

resource "github_repository_environment" "pro" {
  environment = "pro"
  repository  = github_repository.spike.name
  reviewers {
    teams = [github_team.spike.id]
  }
  deployment_branch_policy {
    protected_branches     = false
    custom_branch_policies = true
  }
  depends_on = [github_team_repository.spike]
}

resource "github_repository_environment_deployment_policy" "pro_main" {
  repository     = github_repository.spike.name
  environment    = github_repository_environment.pro.environment
  branch_pattern = "main"
}

resource "github_actions_environment_variable" "role" {
  repository    = github_repository.spike.name
  environment   = github_repository_environment.pro.environment
  variable_name = "AWS_ROLE_ARN"
  value         = "arn:aws:iam::000000000003:role/spike-component-pro-ci"
}

# Both files are committed to main AFTER the ruleset requires PRs: they only
# succeed through the writer App's bypass.
resource "github_repository_file" "codeowners" {
  repository          = github_repository.spike.name
  branch              = "main"
  file                = ".github/CODEOWNERS"
  content             = "* @jellalshadows-idp/spike-team\n"
  overwrite_on_create = true
  depends_on          = [github_repository_ruleset.main]
}

# Writing under .github/workflows needs the App's Workflows permission.
resource "github_repository_file" "workflow" {
  repository          = github_repository.spike.name
  branch              = "main"
  file                = ".github/workflows/hello.yaml"
  content             = "name: hello\non: workflow_dispatch\npermissions: {}\njobs:\n  hello:\n    runs-on: ubuntu-24.04\n    steps:\n      - run: echo hello\n"
  overwrite_on_create = true
  depends_on          = [github_repository_ruleset.main]
}
