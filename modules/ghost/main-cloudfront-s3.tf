
data aws_route53_zone zone {
  name         = local.dns_zone_name
  private_zone = false
}

resource aws_cloudfront_origin_access_identity default {
  comment = "Ghost S3 web bucket for ${local.application}"
}

locals {
  web_origin_id = "ghostStaticOrigin"
}

resource aws_cloudfront_distribution www {
  enabled = true
  comment = local.base_name

  aliases = local.cloudfront_aliases

  viewer_certificate {
    acm_certificate_arn      = local.acm_cert_arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1"
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  //  permission denied from s3
  custom_error_response {
    error_code         = 403
    response_code      = 404
    response_page_path = "/404/index.html"
  }

  custom_error_response {
    error_code         = 404
    response_code      = 404
    response_page_path = "/404/index.html"
  }

  origin {
    domain_name = aws_s3_bucket.web.bucket_regional_domain_name
    origin_id   = local.web_origin_id

    s3_origin_config {
      origin_access_identity = aws_cloudfront_origin_access_identity.default.cloudfront_access_identity_path
    }
  }

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["HEAD", "GET"]
    target_origin_id = local.web_origin_id

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }

    dynamic lambda_function_association {
      for_each = local.viewer_request_lambda_arn
      content {
        event_type   = "viewer-request"
        lambda_arn   = lambda_function_association.value
        include_body = false
      }
    }

    //    3600 1 hour 86400 is 1 day and
    min_ttl                = 3600
    default_ttl            = 86400
    max_ttl                = 31536000
    compress               = true
    viewer_protocol_policy = "redirect-to-https"
  }

}

resource aws_route53_record ghost {
  zone_id = data.aws_route53_zone.zone.zone_id
  name    = local.www_hostname
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.www.domain_name
    zone_id                = aws_cloudfront_distribution.www.hosted_zone_id
    evaluate_target_health = true
  }
}

resource aws_route53_record root {
  count = local.enable_root_domain_count

  zone_id = data.aws_route53_zone.zone.zone_id
  name    = data.aws_route53_zone.zone.name
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.www.domain_name
    zone_id                = aws_cloudfront_distribution.www.hosted_zone_id
    evaluate_target_health = true
  }
}

