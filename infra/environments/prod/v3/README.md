# Prod V3 Terraform 경계

Prod V3 EKS 신규 리소스는 기존 `infra/environments` Terraform Root와 State를 사용한다.

- 기존 GitHub Actions의 Plan·Apply 흐름을 변경하지 않는다.
- 신규 모듈은 `prod/v3` 아래에 격리한다.
- 루트 연결은 `prod-v3.tf`에서만 수행한다.
- 기존 Prod VPC·NAT·Monitoring 인스턴스는 Data Source로 조회한다.
- 기존 Prod V1·V2 리소스의 State 주소를 이동하거나 소유권을 중복 선언하지 않는다.

이 경계로 기존 워크플로우가 PR에서 전체 State를 Plan하고, `main` 반영 뒤 같은 Plan을 Apply한다.
