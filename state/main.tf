terraform {
  required_version = "1.12.6"

  # The code says THAT state and plans are encrypted; TF_ENCRYPTION says HOW (spec §7.2).
  encryption {
    state {
      enforced = true
    }
    plan {
      enforced = true
    }
  }
}

resource "terraform_data" "marker" {
  input = "phase-0-spike"
}
