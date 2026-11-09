# Prod V3 Argo CD Edge

`argocd.lookddak.com`을 Prod EKS의 Argo CD에 연결한다.

```text
Route 53
→ CloudFront + Argo CD 전용 WAF
→ CloudFront VPC Origin
→ GitOps가 만든 Internal NLB:443
→ Istio Gateway https-argocd Listener
→ argocd/argocd-server:80
```

## 소유권 경계

- 이 모듈은 ACM Viewer 인증서, CloudFront VPC Origin·Distribution과 Route 53 A·AAAA Alias만 소유한다.
- 이 모듈은 CloudFront 관리 Prefix List의 443 요청만 허용하는 NLB 전용 Security Group을 만든다.
- NLB는 Kubernetes 태그로 조회만 하며 Terraform State로 가져오지 않는다.
- Argo CD 전용 WAF는 Rate Limit·IP Reputation·공통 규칙을 적용한다.
- GitHub Push payload가 WAF 본문 크기 제한에 걸리지 않도록 정확히 `POST /api/webhook`만 공통 규칙 검사에서 제외한다. 이 경로에도 Rate Limit과 IP Reputation은 계속 적용된다.
- Istio Gateway·HTTPRoute는 GitOps 저장소가 관리한다.

## 적용 순서

1. 이 모듈을 적용해 Edge 리소스와 `gateway_nlb_security_group_id`를 생성한다.
2. 출력된 SG ID를 Prod Gateway의 `service.beta.kubernetes.io/aws-load-balancer-security-groups` annotation에 반영한다.
3. AWS Load Balancer Controller가 NLB에 SG를 연결한 것을 확인한다.
4. CloudFront·DNS 전파 후 UI와 Webhook 경로를 확인한다.

SG 연결 전에도 리소스 생성은 가능하지만 CloudFront에서 Origin으로 실제 요청이 전달된다고 판단하면 안 된다.

## 적용 후 검증

```bash
dig +short argocd.lookddak.com A
curl -I https://argocd.lookddak.com
curl -i -X POST https://argocd.lookddak.com/api/webhook \
  -H 'Content-Type: application/json' \
  -d '{}'
```

DNS와 CloudFront 배포가 완료되면 브라우저에서 Argo CD UI를 확인하고, GitOps 저장소에는 기존 Dev Webhook과 별도로 Prod Webhook을 추가한다.
