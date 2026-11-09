# Prod V3 EKS 용량 점검

2026-11-09 서울 리전 기준으로 기존 서비스 사용량과 Prod V3 기본 용량을 확인했다.

## 네트워크 주소

- Node Subnet: `10.20.31.0/24`, `10.20.32.0/24` — AZ별 AWS 예약분 제외 251 IP
- Pod Subnet: `100.64.0.0/18`, `100.64.64.0/18` — AZ별 AWS 예약분 제외 16,379 IP
- Prefix Delegation 예약: AZ별 `/19` — `/28` Prefix 512개
- Kubernetes Service CIDR: `172.21.0.0/16`

## Service Quota와 현재 사용량

- Standard On-Demand vCPU: 64 중 약 35 사용, System Node 2대가 4 vCPU를 추가해 약 25 vCPU 여유
- ENI: 5,000 중 57개 사용(기존 Prod VPC 12개)
- ALB: 50 중 2개 사용
- NLB: 50 중 1개 사용
- VPC IPv4 CIDR 연결: VPC당 5개 중 Prod VPC 1개 사용, Pod CIDR 추가 후 2개
- EIP: Quota 5보다 많은 6개가 이미 할당되어 있어 신규 EIP·NAT 생성은 불가할 수 있음

이번 구성은 기존 Prod V2 NAT Gateway를 재사용하므로 EIP를 추가하지 않는다. 다만 단일 NAT가 `ap-northeast-2c`에 있어 `2a` Node·Pod의 외부 통신은 AZ 간 비용과 단일 장애점이 남는다. 운영 안정화 단계에서 EIP Quota를 확보한 뒤 AZ별 NAT로 전환할지 별도 결정한다.
