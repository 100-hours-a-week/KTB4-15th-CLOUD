# lookddak

nginx를 단일 진입점으로 두고 Next.js(프론트) · Spring(백엔드) · FastAPI(데이터 처리) · PostgreSQL을 docker compose로 묶은 프로젝트.

```
                    ┌────────────┐
   80/443 ──────────▶   nginx    │
                    └─────┬──────┘
                          │
              ┌───────────┼───────────┐
              ▼                       ▼
        ┌──────────┐            ┌──────────┐
        │  nextjs   │            │  spring   │
        └──────────┘            └─────┬────┘
                                       ▼
                                 ┌──────────┐
                                 │ fastapi   │
                                 └─────┬────┘
                                       ▼
                                 ┌──────────┐
                                 │postgresql │
                                 └──────────┘
```

## 디렉터리 구조

```
.
├── .env.example
├── .dockerignore
├── .gitignore
├── readme.md
├── docker-compose.yaml           # 운영 기준 설정 (awslogs 로깅 등)
├── docker-compose-local.yml      # 로컬 전용 오버라이드 (-f로 명시적으로만 사용)
├── nginx/
│   └── conf.d/
│       └── default.conf
├── nextjs/
│   └── Dockerfile
├── spring/
│   └── Dockerfile
└── fastapi/
    └── Dockerfile
```

## 사전 준비

- Docker / Docker Compose v2
- 이미지 빌드는 각 서비스 `Dockerfile`이 컨테이너 안에서 처리하므로 호스트에 필수는 아님
- nextjs / spring / fastapi 폴더 별 소스코드

## 환경 변수

```bash
cp .env.example .env
```

## 실행

`docker-compose.yaml`은 운영 기준 설정이라 `logging: awslogs`를 그대로 쓴다 — 로컬에는 AWS 자격 증명이 없어 이 상태로는 컨테이너가 뜨지 않는다. 로컬에서는 반드시 `docker-compose-local.yml`을 같이 지정한다 (로깅 드라이버를 `json-file`로 교체):

```bash
docker compose -f docker-compose.yaml -f docker-compose-local.yml up -d --build
```

`nextjs` / `spring` / `fastapi`는 `image`(ECR)와 `build`(로컬 Dockerfile)를 함께 지정해뒀기 때문에, 로컬에 해당 이미지가 없으면 각 서비스 디렉터리의 Dockerfile로 자동 빌드된다.

### 상태 확인

```bash
docker compose -f docker-compose.yaml -f docker-compose-local.yml ps
docker compose -f docker-compose.yaml -f docker-compose-local.yml logs -f <service>
```


### 특정 서비스만 재배포

```bash
docker compose -f docker-compose.yaml -f docker-compose-local.yml up -d --build --no-deps <service>
```

### 종료

```bash
docker compose -f docker-compose.yaml -f docker-compose-local.yml down       # 볼륨(DB 데이터)은 유지
docker compose -f docker-compose.yaml -f docker-compose-local.yml down -v    # 볼륨까지 삭제
```


