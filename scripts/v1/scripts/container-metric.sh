#!/bin/bash
# 컨테이너와 호스트 상태를 1분마다 CloudWatch Logs로 전송
# 로그 그룹의 메트릭 필터가 JSON에서 숫자를 뽑아 Lookddak/Docker 메트릭으로 변환함
#
# cron: * * * * * /usr/local/bin/container-metrics.sh >> /var/log/container-status.err 2>&1

export PATH=$PATH:/snap/bin:/usr/local/bin

REGION=ap-northeast-2
LOG_GROUP=/lookddak/prod/status
LOG_STREAM=lookddak-v1-ec2-metric
CONTAINERS="lookddak-nextjs lookddak-fastapi lookddak-spring lookddak-postgresql lookddak-nginx"

NOW=$(date -Is)
is_num() { [[ "$1" =~ ^[0-9]+(\.[0-9]+)?$ ]]; }

# 1. 실행 중인 컨테이너의 CPU, 메모리
declare -A CPU MEM MEMUSE
while IFS='|' read -r name cpu mem memuse; do
  CPU[$name]=${cpu%\%}
  MEM[$name]=${mem%\%}
  MEMUSE[$name]=$memuse
done < <(docker stats --no-stream --format '{{.Name}}|{{.CPUPerc}}|{{.MemPerc}}|{{.MemUsage}}')

# 2. 컨테이너별 상세 상태
lines=""
down=0
down_list=""
mem_max=0
mem_max_name=""

for c in $CONTAINERS; do
  info=$(docker inspect -f '{{.State.Status}}|{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}|{{.RestartCount}}|{{.State.OOMKilled}}|{{.State.ExitCode}}|{{.State.StartedAt}}' "$c" 2>/dev/null)
  IFS='|' read -r status health restarts oom exit_code started <<< "$info"
  status=${status:-missing}
  health=${health:-none}
  restarts=${restarts:-0}
  oom=${oom:-false}
  exit_code=${exit_code:-0}

  # 없거나, 멈췄거나, unhealthy면 다운으로 집계
  up=true
  if [[ "$status" != "running" || "$health" == "unhealthy" ]]; then
    up=false
    down=$((down + 1))
    down_list+="$c "
  fi

  cpu=${CPU[$c]:-}
  mem=${MEM[$c]:-}
  is_num "$cpu" || cpu=null
  is_num "$mem" || mem=null

  # 메모리 사용률이 가장 높은 컨테이너 기록
  if [[ "$mem" != null ]] && awk -v a="$mem_max" -v b="$mem" 'BEGIN { exit !(b > a) }'; then
    mem_max=$mem
    mem_max_name=$c
  fi

  lines+=$(printf '{"type":"container","time":"%s","name":"%s","up":%s,"status":"%s","health":"%s","cpu_percent":%s,"mem_percent":%s,"mem_usage":"%s","restart_count":%s,"oom_killed":%s,"exit_code":%s,"started_at":"%s"}' \
    "$NOW" "$c" "$up" "$status" "$health" "$cpu" "$mem" "${MEMUSE[$c]:-}" "$restarts" "$oom" "$exit_code" "$started")$'\n'
done

# 3. 호스트 메모리 (buff/cache 제외 실제 사용률), 루트 디스크, 1분 평균 부하
host_mem=$(free | awk '/^Mem:/ { printf "%.1f", (1 - $7 / $2) * 100 }')
host_disk=$(df --output=pcent / | tail -1 | tr -dc '0-9')
load1=$(cut -d' ' -f1 /proc/loadavg)
is_num "$host_mem" || host_mem=0
is_num "$host_disk" || host_disk=0
is_num "$load1" || load1=0

# 4. 요약 줄 (메트릭 필터 대상)
lines+=$(printf '{"type":"summary","time":"%s","containers_down":%d,"down_list":"%s","container_mem_max":%s,"container_mem_max_name":"%s","host_mem":%s,"host_disk":%s,"load1":%s}' \
  "$NOW" "$down" "${down_list% }" "$mem_max" "$mem_max_name" "$host_mem" "$host_disk" "$load1")$'\n'

# 5. CloudWatch Logs로 한 번에 전송
ts=$(date +%s%3N)
events=$(printf '%s' "$lines" | python3 -c '
import json, sys
ts = int(sys.argv[1])
print(json.dumps([{"timestamp": ts, "message": l} for l in sys.stdin.read().splitlines() if l]))
' "$ts")

aws logs put-log-events --region "$REGION" \
  --log-group-name "$LOG_GROUP" \
  --log-stream-name "$LOG_STREAM" \
  --log-events "$events" > /dev/null
