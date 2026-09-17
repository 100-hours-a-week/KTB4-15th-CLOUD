# syntax=docker/dockerfile:1

# =========================
# Build stage
# - Gradle 테스트 실행
# - Spring Boot bootJar 생성
# - jar를 레이어별로 추출
# =========================
FROM eclipse-temurin:25-jdk-noble AS builder

WORKDIR /build

# Gradle 설정 파일을 먼저 복사해 의존성 다운로드 레이어를 캐시한다.
COPY gradlew .
COPY gradle gradle
COPY build.gradle settings.gradle ./

# gradlew 실행 권한을 보장하고 의존성을 미리 받아둔다.
RUN chmod +x gradlew && ./gradlew dependencies --no-daemon

# 소스 코드는 의존성 설치 후 복사해 캐시 효율을 높인다.
COPY src src

# CI에서 builder stage를 빌드하므로 테스트를 이 단계에서 실행한다.
# bootJar 산출물 이름은 build.gradle에서 app.jar로 고정한다.
RUN ./gradlew test bootJar --no-daemon

# Spring Boot jar를 Docker layer cache에 유리하도록 분리한다.
RUN java -Djarmode=tools -jar build/libs/app.jar extract --layers --launcher --destination extracted


# =========================
# Runtime stage
# - JRE 기반 최종 실행 이미지
# - 빌드 도구 없이 실행 파일만 포함
# =========================
FROM eclipse-temurin:25-jre-noble AS runtime

# 애플리케이션은 root 권한이 필요 없으므로 non-root 사용자로 실행한다.
RUN groupadd --system --gid 1001 spring \
 && useradd --system --uid 1001 --gid spring spring

WORKDIR /app

# 덜 자주 바뀌는 레이어부터 복사해 이미지 push/pull 효율을 높인다.
COPY --from=builder /build/extracted/dependencies/ ./
COPY --from=builder /build/extracted/spring-boot-loader/ ./
COPY --from=builder /build/extracted/snapshot-dependencies/ ./
COPY --from=builder /build/extracted/application/ ./

USER spring

# 문서화용 포트 선언. 실제 노출은 compose/ECS 설정에서 결정한다.
EXPOSE 8080

# 메모리 튜닝값(-Xms, -Xmx, timezone 등)은 JAVA_TOOL_OPTIONS로 외부에서 주입한다.
# 레이어 추출 방식이므로 app.jar가 아니라 JarLauncher로 실행한다.
ENTRYPOINT ["java", "-XX:+ExitOnOutOfMemoryError", "org.springframework.boot.loader.launch.JarLauncher"]