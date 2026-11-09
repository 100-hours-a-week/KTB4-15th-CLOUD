# Argo CD 전용 WAF
# - UI·API에는 공통 보호 규칙을 적용한다.
# - GitHub Push payload는 클 수 있으므로 POST /api/webhook만 CRS Body 검사에서 제외한다.
# - Webhook도 Rate Limit과 IP Reputation 검사는 통과해야 한다.
resource "aws_wafv2_web_acl" "argocd" {
  provider = aws.us_east_1

  name        = "lookddak-prod-v3-argocd"
  description = "Protection for the LookDDak Prod V3 Argo CD CloudFront distribution"
  scope       = "CLOUDFRONT"

  default_action {
    allow {}
  }

  rule {
    name     = "rate-limit"
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
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "lookddak-prod-v3-argocd-rate-limit"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "amazon-ip-reputation-list"
    priority = 1

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
      metric_name                = "lookddak-prod-v3-argocd-ip-reputation"
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

        scope_down_statement {
          not_statement {
            statement {
              and_statement {
                statement {
                  byte_match_statement {
                    positional_constraint = "EXACTLY"
                    search_string         = "POST"

                    field_to_match {
                      method {}
                    }

                    text_transformation {
                      priority = 0
                      type     = "NONE"
                    }
                  }
                }

                statement {
                  byte_match_statement {
                    positional_constraint = "EXACTLY"
                    search_string         = "/api/webhook"

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
      metric_name                = "lookddak-prod-v3-argocd-common-rule-set"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "lookddak-prod-v3-argocd"
    sampled_requests_enabled   = true
  }

  tags = merge(local.common_tags, {
    Name = "lookddak-prod-v3-argocd"
  })
}
