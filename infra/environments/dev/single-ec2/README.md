# Single Dev Network and EC2

프로젝트 종료 후 개발 서버 하나에서 Docker Compose로 서비스를 운영하기 위한 최소 인프라입니다.

## 구성

- 전용 VPC `10.30.0.0/16`
- Public Subnet `10.30.1.0/24` (`ap-northeast-2a`)
- Internet Gateway, Public Route Table, Elastic IP
- ARM64 `t4g.xlarge` EC2
- 암호화된 30 GiB Root EBS
- 암호화된 100 GiB Data EBS (`/srv/lookddak`, 삭제 방지)
- SSM Instance Profile
- 외부 인바운드 HTTP 80, HTTPS 443만 허용

SSH 키와 22번 포트는 사용하지 않습니다. 인스턴스 접속은 Terraform output의 `ssm_start_command`를 사용합니다.

Data EBS는 최초 부팅 시 XFS로 포맷하고 `/srv/lookddak`에 마운트합니다. 이미 파일시스템이 존재하면 다시 포맷하지 않습니다.
