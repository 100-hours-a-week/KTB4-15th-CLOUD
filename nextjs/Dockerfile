# builder와 runtime이 같은 Node 버전을 쓰도록 한 곳에서 관리
ARG NODE_IMAGE=node:24-bookworm-slim

# ============ 1단계: 검사 + 빌드 (CI가 검증하는 단계) ============
FROM ${NODE_IMAGE} AS builder
WORKDIR /app
ENV NEXT_TELEMETRY_DISABLED=1

# Node 24에는 corepack이 들어 있음 → pnpm 활성화
RUN corepack enable

# (1) 의존성 목록만 먼저 → 코드만 바뀐 PR은 설치 단계를 캐시에서 재사용
COPY package.json pnpm-lock.yaml ./
RUN pnpm install --frozen-lockfile

# (2) 코드 복사 (.dockerignore 필수)
COPY . .

# (3) 린트 → 빌드(타입 검사 포함). 하나라도 실패하면 이미지가 안 만들어짐
RUN pnpm lint
RUN pnpm build


# ============ 2단계: 런타임 ============
FROM ${NODE_IMAGE} AS runtime
WORKDIR /app

ENV NODE_ENV=production \
    NEXT_TELEMETRY_DISABLED=1 \
    PORT=3000 \
    HOSTNAME=0.0.0.0

RUN groupadd --system --gid 1001 nextjs \
 && useradd  --system --uid 1001 --gid nextjs nextjs

# standalone = 실행에 필요한 파일만 추려진 폴더
COPY --from=builder /app/.next/standalone ./
# standalone에 기본으로 안 들어가는 두 폴더
COPY --from=builder /app/.next/static ./.next/static
COPY --from=builder /app/public ./public

# Next.js가 실행 중 캐시를 쓰는 폴더만 쓰기 권한 부여
RUN mkdir -p .next/cache && chown nextjs:nextjs .next/cache

USER nextjs
EXPOSE 3000

CMD ["node", "server.js"]
