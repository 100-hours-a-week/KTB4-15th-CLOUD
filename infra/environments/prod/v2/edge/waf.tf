resource "aws_wafv2_web_acl" "this" {
  provider = aws.us_east_1

  name        = "lookddak-prod-v2"
  description = "Baseline protection for the LookDDak V2 production CloudFront distribution"
  scope       = "CLOUDFRONT"

  default_action {
    allow {}
  }

  rule {
    name     = "api-rate-limit"
    priority = 0

    action {
      block {
        custom_response {
          response_code = 429
        }
      }
    }

    statement {
      rate_based_statement {
        aggregate_key_type    = "IP"
        evaluation_window_sec = 60
        limit                 = 1200

        scope_down_statement {
          regex_match_statement {
            regex_string = "^/api(/.*)?$"

            field_to_match {
              uri_path {}
            }

            text_transformation {
              priority = 0
              type     = "NONE"
            }
          }
        }
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "lookddak-prod-v2-api-rate-limit"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "web-rate-limit"
    priority = 1

    action {
      block {
        custom_response {
          response_code = 429
        }
      }
    }

    statement {
      rate_based_statement {
        aggregate_key_type    = "IP"
        evaluation_window_sec = 60
        limit                 = 1800

        scope_down_statement {
          and_statement {
            statement {
              not_statement {
                statement {
                  regex_match_statement {
                    regex_string = "^/api(/.*)?$"

                    field_to_match {
                      uri_path {}
                    }

                    text_transformation {
                      priority = 0
                      type     = "NONE"
                    }
                  }
                }
              }
            }

            statement {
              not_statement {
                statement {
                  byte_match_statement {
                    positional_constraint = "STARTS_WITH"
                    search_string         = "/_next/static/"

                    field_to_match {
                      uri_path {}
                    }

                    text_transformation {
                      priority = 0
                      type     = "NONE"
                    }
                  }
                }
              }
            }
          }
        }
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "lookddak-prod-v2-web-rate-limit"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "aws-common-rule-set"
    priority = 2

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "lookddak-prod-v2-common-rule-set"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "amazon-ip-reputation-list"
    priority = 3

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesAmazonIpReputationList"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "lookddak-prod-v2-ip-reputation-list"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "lookddak-prod-v2"
    sampled_requests_enabled   = true
  }

  tags = merge(local.common_tags, {
    Name = "lookddak-prod-v2"
  })
}
