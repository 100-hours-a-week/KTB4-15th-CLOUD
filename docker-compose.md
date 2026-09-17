# docker-compose.yaml 설계 근거

`docker-compose.yaml`을 서비스별로 나눠 구성한 이유와, 각 설정값(네트워크, healthcheck, depends_on, 리소스 제한 등)을 그렇게 잡은 근거를 정리한다.

## 전체 구조

```
                    ┌────────────┐
   80/443 ──────────▶   nginx    │
                    └─────┬──────┘
                          │ app-network
              ┌───────────┼───────────┐
              ▼                       ▼
        ┌──────────┐            ┌──────────┐
        │  nextjs   │            │  spring   │
        └──────────┘            └─────┬────┘
                                       │ app-network
                                       ▼
                                 ┌──────────┐
                                 │ fastapi   │
                                 └─────┬────┘
                                       │ db-network
                                       ▼
                                 ┌──────────┐
                                 │postgresql │
                                 └──────────┘
```

`nginx`만 호스트에 포트를 노출(`ports: 80/443`)하고, 나머지 서비스는 전부 `expose`만 써서 컨테이너 네트워크 내부에서만 접근 가능하다. 외부에서 nextjs/spring/fastapi/postgresql로 직접 들어올 방법이 없고 반드시 nginx를 거치도록 강제하는 구조다.

## 왜 컨테이너별로 나눠 작성했는가

하나의 이미지/프로세스에 프론트(nextjs)·백엔드(spring)·데이터 처리(fastapi)·DB(postgresql)·리버스 프록시(nginx)를 다 넣지 않고 서비스를 쪼갠 이유:

- **언어/런타임이 다름**: Node, JVM, Python, C(nginx)가 한 컨테이너에 같이 있으면 이미지가 비대해지고, 언어별 메모리 튜닝(JVM 힙, V8 old space, Python worker 수)을 독립적으로 걸 수 없다.
- **장애 격리**: 한 서비스가 죽어도 나머지는 살아있어야 한다. 예를 들어 `spring`이 내려가도 `nginx`/`nextjs`는 컨테이너 레벨에서 완전히 독립적이라 정적 화면은 계속 뜬다 (spring에 의존하는 `/api/` 경로만 502).
- **개별 스케일링/재배포**: 트래픽이 몰리는 서비스만 따로 스케일하거나, 코드가 바뀐 서비스만 골라서 재배포(`docker compose up -d --no-deps <service>`)할 수 있다.
- **리소스 상한을 서비스 성격에 맞게 다르게 줄 수 있음**: 아래 표 참고.

## 네트워크 분리 (`app-network` / `db-network`)

- `app-network`: nginx, nextjs, spring, fastapi가 공유. 애플리케이션 계층끼리 통신.
- `db-network`: fastapi, postgresql만 공유. **postgresql은 db-network에만 속해 있어서 app-network에 있는 nginx/nextjs/spring에서는 애초에 접근 경로가 없다.**
- fastapi는 두 네트워크에 다 걸쳐 있어서 "DB에 접근해야 하는 유일한 서비스"로 명시적으로 좁혀놨다. spring이 DB가 필요해지면 fastapi를 거치거나 db-network에 추가해야 하는데, 지금 구조는 DB 접근을 fastapi 하나로 강제하는 셈이다.

## 의존성 체인 (`depends_on` + `condition: service_healthy`)

```
postgresql → fastapi → spring → { nginx, nextjs }
```

- 단순 `depends_on`(컨테이너 생성 순서만 보장)이 아니라 `condition: service_healthy`를 써서, **healthcheck를 통과해야만** 다음 서비스가 시작한다. DB 커넥션이 아직 안 열렸는데 fastapi가 뜨거나, fastapi가 안 떴는데 spring이 뜨는 상황을 막기 위함.
- 단, 이 체크는 **최초 기동 시 1회**만 적용된다. 떠 있는 도중 하위 서비스가 죽어도 상위 서비스가 같이 내려가거나 재시작되진 않는다 (nginx/nextjs는 spring이 죽어도 계속 살아있고, `/api/` 요청만 502를 반환하는 것을 직접 확인함).

## 서비스별 근거

### nginx
- 유일하게 `ports`로 80/443을 호스트에 노출. 나머지는 다 `expose`만 써서 외부 진입점을 nginx 하나로 강제.
- 이미지 리소스(0.5 cpu / 256M)가 다른 서비스보다 작은 이유: 단순 리버스 프록시라 요청을 처리하지 않고 전달만 하므로 CPU/메모리 사용량이 적음.
- `nginx/conf.d`만 마운트하고 `nginx.conf`는 마운트하지 않음: 베이스 이미지의 기본 `nginx.conf`가 이미 `include /etc/nginx/conf.d/*.conf;`를 포함하므로 conf.d만으로 충분.

### nextjs
- `image`(ECR)와 `build`(로컬 `nextjs/Dockerfile`)를 동시에 지정: 운영에서는 CI가 미리 이미지를 ECR에 push해두고 pull만 하면 되지만, 로컬에는 그 이미지가 없으므로 같은 설정 파일로 로컬 빌드도 되게 함 (이미지가 로컬에 없을 때만 build가 트리거됨).
- `NODE_OPTIONS=--max-old-space-size=384`: V8은 컨테이너 memory limit(cgroup)을 인식하지 못하고 호스트 전체 메모리 기준으로 힙을 잡으려 하므로, 컨테이너 limit(512M)의 약 75%로 명시적 상한을 걸어 OOMKilled를 방지.
- healthcheck에 `wget`/`curl` 대신 Node 내장 `http` 모듈을 쓴 이유: `node:*-slim` 이미지엔 기본으로 wget/curl이 없고, 그것 때문에 추가 패키지를 설치하느니 이미 있는 런타임(Node)으로 대체하는 게 이미지 크기·공격면 양쪽에서 유리함.

### spring
- `depends_on: fastapi (healthy)`: spring이 fastapi가 제공하는 데이터/API에 의존한다는 전제. fastapi가 안 뜬 상태로 spring이 먼저 떠서 요청을 받는 것을 막음.
- `JAVA_TOOL_OPTIONS`: `-XX:+UseContainerSupport`로 JVM이 cgroup limit을 인식하게 하고, `-XX:MaxRAMPercentage=75.0`으로 힙 상한을 고정 MB가 아니라 limit 대비 비율로 잡음 (나중에 컨테이너 limit이 바뀌어도 이 값을 다시 안 고쳐도 됨). 메타스페이스는 비율 옵션이 없어 `-XX:MaxMetaspaceSize=192m`로 절대값 지정 (없으면 클래스 로딩이 많은 Spring 특성상 무제한으로 늘어날 수 있음).
- healthcheck가 `bash -c "... /dev/tcp ..."`인 이유: `eclipse-temurin:*-jre-noble`엔 wget/curl이 없다. 처음엔 `CMD-SHELL`로 `/dev/tcp`를 썼다가 계속 실패했는데, 원인은 `CMD-SHELL`이 `/bin/sh`(dash)를 쓰고 dash는 `/dev/tcp`를 지원하지 않기 때문. `CMD`로 `bash`를 명시 호출하도록 고쳐서 해결.
- 리소스가 제일 크다(1 cpu / 1G): JVM 자체의 기본 오버헤드(메타스페이스, JIT, GC)가 Node/Python보다 크기 때문.

### fastapi
- `db-network`에도 속한 유일한 애플리케이션 서비스 — DB 접근이 필요한 서비스를 fastapi로 한정.
- `WEB_CONCURRENCY=1`: Python은 JVM/Node처럼 힙 상한을 거는 옵션이 없어서, 워커 프로세스 수 자체를 제한하는 게 메모리 통제의 핵심 (워커가 늘면 메모리도 그만큼 곱절로 증가).
- `MALLOC_ARENA_MAX=2`: glibc malloc이 멀티스레드 환경에서 락 경합을 줄이려 아레나를 계속 늘리는데, 그 과정에서 파편화로 실사용량보다 훨씬 큰 RSS를 점유하게 됨 (컨테이너 OOMKilled의 흔한 원인). 아레나 수를 2개로 제한해 방지.
- `UVICORN_TIMEOUT_GRACEFUL_SHUTDOWN=30` (< `stop_grace_period: 40s`): uvicorn 기본값은 무제한 대기라 오래 걸리는 요청 하나 때문에 종료가 계속 지연되다 SIGKILL을 맞을 수 있음. graceful shutdown 시간을 stop_grace_period보다 짧게 잡아 SIGKILL 전에 정상 종료를 마칠 시간을 확보.
- `POSTGRES_HOST/PORT/DB/USER/PASSWORD` + `DATABASE_URL`: postgresql 서비스와 동일한 `.env` 값을 공유해 접속 정보를 맞춤. 개별 필드 방식(Pydantic `BaseSettings` 등)과 커넥션 문자열 방식(SQLAlchemy 등) 둘 다 대응 가능하도록 같이 넣어둠 — 실제 앱 코드가 어느 쪽을 쓰는지에 따라 한쪽은 정리해도 됨.
- healthcheck가 Python 내장 `urllib.request`인 이유: 위 nextjs/spring과 동일하게, 이미지에 없는 wget/curl 대신 이미 있는 언어 런타임으로 대체.

### postgresql
- `db-network`에만 속함 — app-network에 있는 nginx/nextjs/spring에서는 네트워크 경로 자체가 없어 접근 불가. fastapi를 거치지 않고는 DB에 닿을 수 없는 구조.
- `command`의 postgres 튜닝 파라미터는 컨테이너 limit(1G) 기준: `shared_buffers`는 전체의 ~25%, `effective_cache_size`는 실제 할당이 아니라 쿼리 플래너 힌트값, `work_mem`은 커넥션당 소모라 낮게 유지.
- `reservations.memory: 512M`: Docker Engine에 실제 대응하는 `--memory-reservation` 옵션이 있어 단일 호스트에서도 동작하는 soft limit. 반면 `reservations.cpus`는 원래 Docker Swarm 스케줄러가 노드 배치 판단에 쓰는 값이라, Swarm 없이 `docker compose up`만 쓰는 지금 환경에서는 대응하는 엔진 옵션이 없어 무시된다 (실측 확인: `docker inspect`의 `CpuShares`/`CpuQuota`가 0으로 반영 안 됨).

### certbot
- `profiles: ["ssl"]`로 지정해 `docker compose up` 시 자동 실행되지 않게 함. 인증서 발급/갱신은 상시 필요한 작업이 아니라 명시적으로 호출할 때만 필요하기 때문.
- nginx와 볼륨(`certbot-certs`, `certbot-challenge`)을 공유: 발급된 인증서를 nginx가 읽어야 하고, HTTP-01 challenge 검증 요청도 nginx가 응답해야 하기 때문.

## 공통 패턴

| 패턴 | 이유 |
|---|---|
| 모든 healthcheck가 wget/curl 대신 언어 내장 도구(Node http, Python urllib, bash /dev/tcp) 사용 | 베이스 이미지(slim/noble)에 wget/curl이 기본 설치돼 있지 않음. 패키지를 추가 설치하느니 이미 있는 런타임으로 대체해 이미지 크기와 공격면을 줄임 |
| `deploy.resources.limits` (cpus/memory) | Docker Compose v2는 Swarm 없이도 이 값을 cgroup 제한으로 직접 적용함 (실측 확인: `docker inspect`의 `NanoCPUs`/`Memory`에 그대로 반영). `reservations.cpus`만 예외적으로 Swarm 전용이라 무시됨 |
| `stop_grace_period` > 앱 자체의 graceful shutdown 타임아웃 | SIGTERM을 받은 프로세스가 정상 종료를 마칠 시간을 먼저 확보하고, 그래도 안 끝나면 Docker가 SIGKILL로 강제 종료 |
| `logging: awslogs` (전 서비스 공통) | 운영(ECS 등)에서 CloudWatch Logs로 중앙 수집하기 위함. **로컬에는 AWS 자격증명이 없어 이 드라이버로 컨테이너가 아예 뜨지 못하므로, `docker-compose.override.yml`에서 로컬 전용으로 `json-file`로 교체한다** (`docker-compose.yaml` 자체는 운영 설정 그대로 유지) |
| `image` + `build` 동시 지정 (nextjs/spring/fastapi) | 운영은 CI가 미리 push한 ECR 이미지를 pull, 로컬은 그 이미지가 없으므로 같은 파일로 자동 로컬 빌드 (이미지가 로컬에 이미 있으면 빌드를 건너뜀) |

## 로컬 전용 파일

- `docker-compose.override.yml`: `docker compose` CLI가 `docker-compose.yaml`과 자동으로 병합하는 파일. 로컬에서 `awslogs` 드라이버 때문에 컨테이너가 못 뜨는 문제를 여기서만 `json-file`로 교체해 해결한다. **운영 서버(EC2 등)에는 이 파일을 배포하지 않아야** 운영 설정(`awslogs`)이 의도치 않게 덮어써지지 않는다.
