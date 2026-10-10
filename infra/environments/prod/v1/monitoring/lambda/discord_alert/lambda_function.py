"""
Discord 알림 Lambda (EventBridge → SQS → Lambda)

SQS 메시지 본문(EventBridge 이벤트)을 꺼내 Discord로 전송.
실패한 메시지만 batchItemFailures로 돌려줘서 SQS가 다시 보내게 하고,
계속 실패하면 SQS 재시도 한도를 넘긴 뒤 DLQ로 이동.

처리하는 EventBridge 이벤트
  - CloudWatch 알람 상태 변경  (source: aws.cloudwatch)
      · 상태 로그 기반 메트릭(ContainersDown 등) 알람이면
        CloudWatch Logs에서 알람 시점의 상태 로그를 읽어 카드에 함께 표시
      · 그 외는 알람 내용만 전송
  - RDS 인스턴스 이벤트         (source: aws.rds, 장애·페일오버·재부팅·스토리지·유지보수·복구)
      → critical 채널
  - Nginx 트래픽 알람           (lookddak-nginx-* 알람: 5xx 수, 요청 수)
      · 기준 초과(ALARM)만 "요청량 초과", "5xx 응답 증가" 경고(주황)로 전송하고 복구(OK) 알림은 보내지 않음
  - 컨테이너 상태 변화          (source: custom.docker, EC2의 docker-alert.sh가 전송)
  - EC2 인스턴스 상태 변경     (source: aws.ec2)
  - AWS Health 이벤트           (source: aws.health)
      → warning 채널

Discord 웹훅 URL (SSM Parameter Store, SecureString)
  /lookddak/prod/discord/critical-webhook-url : CloudWatch 알람·RDS 이벤트용
  /lookddak/prod/discord/warning-webhook-url  : Nginx 트래픽 알람·컨테이너·EC2·AWS Health 이벤트용
  → 콜드 스타트 때 한 번 읽어서 재사용 (호출마다 SSM을 부르지 않음)

환경 변수 (선택)
  STATUS_LOG_GROUP    : 상태 로그 그룹 (기본 /lookddak/prod/status)
  STATUS_LOG_STREAM   : 상태 로그 스트림 (기본 lookddak-v1-ec2-metric)

필요 권한 (Lambda 실행 역할)
  logs:GetLogEvents  on  상태 로그 그룹
  ssm:GetParameter   on  /lookddak/prod/discord/*
"""

import json
import os
import time
import urllib.error
import urllib.request
from datetime import datetime, timedelta, timezone
from urllib.parse import quote

import boto3

CRITICAL_WEBHOOK_PARAM = "/lookddak/prod/discord/critical-webhook-url"
WARNING_WEBHOOK_PARAM = "/lookddak/prod/discord/warning-webhook-url"


def get_secure_parameter(name):
    """SSM Parameter Store의 SecureString 값을 복호화해서 가져온다."""
    res = boto3.client("ssm").get_parameter(Name=name, WithDecryption=True)
    return res["Parameter"]["Value"]


CRITICAL_WEBHOOK_URL = get_secure_parameter(CRITICAL_WEBHOOK_PARAM)   # CloudWatch 알람·RDS 이벤트
WARNING_WEBHOOK_URL = get_secure_parameter(WARNING_WEBHOOK_PARAM)     # Nginx 트래픽 알람·컨테이너·EC2·AWS Health 이벤트
STATUS_LOG_GROUP = os.environ.get("STATUS_LOG_GROUP", "/lookddak/prod/status")
STATUS_LOG_STREAM = os.environ.get("STATUS_LOG_STREAM", "lookddak-v1-ec2-metric")
REGION = os.environ.get("AWS_REGION", "ap-northeast-2")

KST = timezone(timedelta(hours=9))
EMBEDS_PER_MESSAGE = 10      # Discord 메시지 1개에 넣을 수 있는 최대 카드 수
MESSAGE_CHAR_LIMIT = 5500    # Discord 메시지 1개의 카드 전체 글자 수 한도(6000)보다 여유 있게

# 상태 로그(/lookddak/prod/status)에서 메트릭 필터로 만든 메트릭
# 이 메트릭을 쓰는 알람은 상태 로그를 읽어 함께 보냄
STATUS_METRICS = {
    "ContainersDown",
    "ContainerMemMaxPercent",
    "HostMemPercent",
    "HostDiskPercent",
    "Load1",
}

# Nginx access log에서 메트릭 필터로 만든 메트릭 (메트릭 이름·필터 이름 모두 포함)
# 이 메트릭을 쓰는 알람은 warnning 채널로 보내고, 복구(OK) 알림은 보내지 않음
NGINX_METRICS = {
    "ApiServerErrorCount",
    "ApiRequestCount",
    "nginx-api-5xx-count",
    "nginx-api-request-count",
}
NGINX_ALARM_PREFIX = "lookddak-nginx-"   # 메트릭 정보가 없는 이벤트(테스트 등) 대비


def is_nginx_alarm(name, metrics):
    return name.startswith(NGINX_ALARM_PREFIX) or bool(set(metrics) & NGINX_METRICS)


def nginx_label(name, metrics):
    """Nginx 트래픽 알람의 카드 제목 앞말. 장애가 아니라 트래픽 경고임을 드러냄."""
    m = set(metrics)
    if m & {"ApiServerErrorCount", "nginx-api-5xx-count"} or "5xx" in name:
        return "5xx 응답 증가"
    if m & {"ApiRequestCount", "nginx-api-request-count"} or "request" in name:
        return "요청량 초과"
    return "트래픽 경고"


COLORS = {
    "ALARM": 0xE24B4A,      # 빨강
    "OK": 0x1D9E75,         # 초록
    "WARNING": 0xEF9F27,    # 주황
    "INFO": 0x378ADD,       # 파랑
    "MUTED": 0x888780,      # 회색
}

# docker-alert.sh 알림 종류 → 카드 색상
DOCKER_KIND_STATE = {
    "DOWN": "ALARM",
    "OOM": "ALARM",
    "UNHEALTHY": "WARNING",
    "STOP": "MUTED",
    "START": "INFO",
    "HEALTHY": "OK",
}

logs = boto3.client("logs")


def truncate(text, limit=1000):
    text = str(text or "")
    return text if len(text) <= limit else text[: limit - 3] + "..."


def to_kst(iso):
    """ISO 시각 문자열을 KST 'MM-DD HH:MM:SS'로. 실패하면 원문."""
    try:
        return datetime.fromisoformat(iso.replace("Z", "+00:00")).astimezone(KST).strftime("%m-%d %H:%M:%S")
    except (ValueError, AttributeError):
        return str(iso)


# ── 상태 로그 조회 ──────────────────────────────────────────

def alarm_metric_names(detail):
    """알람이 사용하는 메트릭 이름 목록 (계산식 알람이면 여러 개)."""
    names = []
    for m in (detail.get("configuration") or {}).get("metrics") or []:
        name = ((m.get("metricStat") or {}).get("metric") or {}).get("name")
        if name:
            names.append(name)
    return names


def alarm_time_ms(detail):
    """알람 상태가 바뀐 시각(ms). 없으면 현재 시각."""
    ts = (detail.get("state") or {}).get("timestamp", "")
    for fmt in ("%Y-%m-%dT%H:%M:%S.%f%z", "%Y-%m-%dT%H:%M:%S%z"):
        try:
            return int(datetime.strptime(ts, fmt).timestamp() * 1000)
        except ValueError:
            continue
    return int(time.time() * 1000)


def fetch_status_snapshot(at_ms):
    """알람 시각 직전의 상태 로그 한 묶음(summary 1줄 + container 5줄)을 가져옴."""
    res = logs.get_log_events(
        logGroupName=STATUS_LOG_GROUP,
        logStreamName=STATUS_LOG_STREAM,
        startTime=at_ms - 5 * 60 * 1000,
        endTime=at_ms + 1000,
        startFromHead=False,
        limit=30,
    )
    rows = []
    for e in res.get("events", []):
        try:
            rows.append(json.loads(e["message"]))
        except (ValueError, KeyError):
            continue
    summaries = [r for r in rows if r.get("type") == "summary"]
    if not summaries:
        return None
    summary = summaries[-1]  # 가장 최근 묶음
    containers = [r for r in rows if r.get("type") == "container" and r.get("time") == summary.get("time")]
    return {"summary": summary, "containers": containers}


def fmt_pct(v):
    return "-" if v is None else f"{float(v):.1f}%"


def describe_snapshot(snap, metric_names):
    """메트릭 종류에 맞게 상태 로그를 사람이 읽기 쉬운 문장으로."""
    s = snap["summary"]
    containers = snap["containers"]
    lines = []

    if "ContainersDown" in metric_names:
        down = [c for c in containers if not c.get("up")]
        if down:
            lines.append("**다운 컨테이너**")
            lines.append("```")
            for c in down:
                lines.append(
                    f"{c.get('name')}: {c.get('status')}/{c.get('health')}, "
                    f"exit {c.get('exit_code')}, OOM {str(c.get('oom_killed')).lower()}, "
                    f"재시작 {c.get('restart_count')}회"
                )
            lines.append("```")
        else:
            lines.append("다운 컨테이너 없음")

    if metric_names & {"ContainerMemMaxPercent", "HostMemPercent"}:
        ranked = sorted(containers, key=lambda c: c.get("mem_percent") or 0, reverse=True)
        lines.append("**컨테이너 메모리 (높은 순)**")
        lines.append("```")
        for c in ranked:
            lines.append(f"{c.get('name', '-'):<22}{fmt_pct(c.get('mem_percent')):>7}  {c.get('mem_usage', '')}")
        lines.append("```")

    # 공통 요약
    lines.append(
        f"호스트 메모리 {fmt_pct(s.get('host_mem'))} · 디스크 {s.get('host_disk', '-')}% · "
        f"load1 {s.get('load1', '-')} · 다운 {s.get('containers_down', '-')}개"
    )
    lines.append(f"로그 시각: {to_kst(s.get('time'))} KST")
    return "\n".join(lines)


def logs_console_url():
    enc = lambda s: quote(quote(s, safe=""), safe="").replace("%", "$")
    return (
        f"https://{REGION}.console.aws.amazon.com/cloudwatch/home?region={REGION}"
        f"#logsV2:log-groups/log-group/{enc(STATUS_LOG_GROUP)}/log-events/{enc(STATUS_LOG_STREAM)}"
    )


# ── EventBridge 이벤트 파싱 ─────────────────────────────────

def from_cloudwatch(detail):
    name = detail["alarmName"]
    old = detail["previousState"]["value"]
    new = detail["state"]["value"]
    # 알람 생성 직후나 데이터 공백 뒤 복귀는 알리지 않음
    if old == "INSUFFICIENT_DATA" and new == "OK":
        return None

    metrics = alarm_metric_names(detail)
    nginx = is_nginx_alarm(name, metrics)
    # Nginx 트래픽 알람은 복구(OK) 알림을 보내지 않음
    if nginx and new == "OK":
        return None

    if nginx:
        label = nginx_label(name, metrics)
    else:
        label = "장애" if new == "ALARM" else "복구" if new == "OK" else "상태 변경"
    fields = [("상태", f"{old} → {new}")]
    if metrics:
        fields.append(("메트릭", ", ".join(metrics)))

    description = truncate(detail["state"].get("reason", ""), 500)

    # 상태 로그 기반 알람이면 알람 시점의 상태 로그를 붙임 (nginx 등은 그대로)
    status_metrics = set(metrics) & STATUS_METRICS
    if status_metrics:
        try:
            snap = fetch_status_snapshot(alarm_time_ms(detail))
            if snap:
                description += "\n\n" + describe_snapshot(snap, status_metrics)
            else:
                description += "\n\n상태 로그를 찾지 못함 (최근 5분 내 로그 없음. 스크립트·전송 중단 가능성)"
        except Exception as e:
            print("log fetch error:", e)
            description += f"\n\n상태 로그 조회 실패: {truncate(e, 200)}"
        description += f"\n[상태 로그 보기]({logs_console_url()})"

    return {
        "title": f"{label}: {name}",
        "state": "WARNING" if nginx and new == "ALARM" else new,   # Nginx 경고는 주황색
        "webhook": WARNING_WEBHOOK_URL if nginx else CRITICAL_WEBHOOK_URL,
        "description": truncate(description, 3500),
        "fields": fields,
    }


def from_ec2(detail):
    state = detail.get("state", "")
    level = "WARNING" if state in ("stopping", "stopped", "shutting-down", "terminated") else "INFO"
    return {
        "title": f"EC2 상태 변경: {detail.get('instance-id', '-')}",
        "state": level,
        "webhook": WARNING_WEBHOOK_URL,
        "description": f"인스턴스 상태가 `{state}`(으)로 변경됨",
        "fields": [("상태", state)],
    }


def from_health(detail):
    desc = ""
    descriptions = detail.get("eventDescription") or []
    if descriptions:
        desc = descriptions[0].get("latestDescription", "")
    entities = [e.get("entityValue", "") for e in detail.get("affectedEntities") or []]
    category = detail.get("eventTypeCategory", "")
    fields = [
        ("서비스", detail.get("service", "-")),
        ("분류", category or "-"),
        ("이벤트", detail.get("eventTypeCode", "-")),
    ]
    if entities:
        fields.append(("영향 리소스", truncate(", ".join(entities), 500)))
    if detail.get("startTime"):
        fields.append(("시작", detail["startTime"]))
    return {
        "title": f"AWS Health: {detail.get('eventTypeCode', '알림')}",
        "state": "ALARM" if category == "issue" else "WARNING",
        "webhook": WARNING_WEBHOOK_URL,
        "description": truncate(desc),
        "fields": fields,
    }


def from_docker(detail):
    kind = detail.get("kind", "INFO")
    name = detail.get("container", "-")
    lines = [detail.get("message", "")]
    if kind == "START" and detail.get("image"):
        lines[0] += f", 이미지 `{detail['image']}`"
    lines.append(f"호스트 `{detail.get('host', '-')}` · 발생 {to_kst(detail.get('time'))} KST")
    if detail.get("logs"):
        lines.append("```\n" + truncate(detail["logs"], 1500).replace("```", "'''") + "\n```")
    return {
        "title": f"[{kind}] {name}",
        "state": DOCKER_KIND_STATE.get(kind, "INFO"),
        "description": truncate("\n".join(lines), 3500),
        "fields": [],
        "webhook": WARNING_WEBHOOK_URL,
    }


# RDS 이벤트 카테고리 → (표시 이름, 카드 색상)
RDS_CATEGORIES = {
    "failure": ("장애", "ALARM"),
    "failover": ("페일오버", "ALARM"),
    "availability": ("재부팅·중지", "WARNING"),
    "low storage": ("스토리지 부족", "ALARM"),
    "maintenance": ("유지보수", "INFO"),
    "recovery": ("복구", "OK"),
    "notification": ("알림", "INFO"),
}
SEVERITY = ["ALARM", "WARNING", "OK", "INFO"]  # 여러 카테고리일 때 앞쪽 우선


def from_rds(detail):
    categories = detail.get("EventCategories") or []
    db = detail.get("SourceIdentifier") or detail.get("SourceArn", "-").split(":")[-1]

    labels = [RDS_CATEGORIES.get(c, (c, "INFO"))[0] for c in categories] or ["이벤트"]
    states = [RDS_CATEGORIES.get(c, (c, "INFO"))[1] for c in categories] or ["INFO"]
    state = min(states, key=SEVERITY.index)

    return {
        "title": f"RDS {' · '.join(labels)}: {db}",
        "state": state,
        "description": truncate(
            f"{detail.get('Message', '')}\n발생 {to_kst(detail.get('Date'))} KST", 1500
        ),
        "fields": [
            ("이벤트 ID", detail.get("EventID", "-")),
            ("카테고리", ", ".join(categories) or "-"),
        ],
        "webhook": CRITICAL_WEBHOOK_URL,
    }


PARSERS = {
    "aws.cloudwatch": from_cloudwatch,
    "aws.ec2": from_ec2,
    "aws.health": from_health,
    "aws.rds": from_rds,
    "custom.docker": from_docker,
}


def parse_event(event):
    """EventBridge 이벤트를 Discord 카드 정보로 변환. 알릴 필요 없으면 None."""
    parser = PARSERS.get(event.get("source"))
    if parser is None:
        # 규칙에 다른 이벤트가 연결됐을 때 조용히 사라지지 않도록 원문을 보냄
        return {
            "title": f"처리하지 않는 이벤트: {event.get('source', '-')}",
            "state": "INFO",
            "webhook": WARNING_WEBHOOK_URL,
            "description": truncate(json.dumps(event, ensure_ascii=False), 1500),
            "fields": [],
        }
    return parser(event["detail"])


# ── Discord 전송 ────────────────────────────────────────────

def to_embed(alert):
    return {
        "title": truncate(alert["title"], 250),
        "description": alert["description"],
        "color": COLORS.get(alert["state"], COLORS["INFO"]),
        "fields": [{"name": k, "value": truncate(v, 1000), "inline": True} for k, v in alert["fields"]],
        "footer": {"text": datetime.now(KST).strftime("%Y-%m-%d %H:%M:%S KST")},
    }


def embed_size(embed):
    return (
        len(embed["title"]) + len(embed["description"]) + len(embed["footer"]["text"])
        + sum(len(f["name"]) + len(f["value"]) for f in embed["fields"])
    )


def send_discord(alerts, webhook_url, retry_on_rate_limit=True):
    """카드 여러 장을 메시지 하나로 전송. 실패하면 예외."""
    req = urllib.request.Request(
        webhook_url,
        data=json.dumps({"embeds": [to_embed(a) for a in alerts]}).encode(),
        headers={
            "Content-Type": "application/json",
            "User-Agent": "lookddak-alert-bot/1.0",  # 없으면 Discord가 403으로 차단할 수 있음
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=10) as res:
            return res.status
    except urllib.error.HTTPError as e:
        body = e.read().decode(errors="ignore")
        # 요청 한도 초과: 기다릴 시간이 짧으면 한 번만 재시도
        if e.code == 429 and retry_on_rate_limit:
            try:
                wait = float(json.loads(body).get("retry_after", 1))
            except (ValueError, AttributeError):
                wait = 1.0
            if wait <= 5:
                time.sleep(wait)
                return send_discord(alerts, webhook_url, retry_on_rate_limit=False)
        raise RuntimeError(f"Discord 전송 실패: {e.code} {body}") from e


def chunk_for_discord(pending):
    """카드 수(10장)와 메시지 전체 글자 수(6000자) 한도를 모두 지키도록 묶음."""
    chunk, size = [], 0
    for item in pending:
        s = embed_size(to_embed(item[1]))
        if chunk and (len(chunk) >= EMBEDS_PER_MESSAGE or size + s > MESSAGE_CHAR_LIMIT):
            yield chunk
            chunk, size = [], 0
        chunk.append(item)
        size += s
    if chunk:
        yield chunk


# ── 진입점 (SQS 트리거) ─────────────────────────────────────

def lambda_handler(event, context):
    failures = []
    pending = []  # (messageId, alert)

    for r in event.get("Records", []):
        try:
            alert = parse_event(json.loads(r["body"]))
        except Exception as e:
            print(f"parse error {r['messageId']}: {e}")
            failures.append(r["messageId"])
            continue
        if alert is None:
            print("skip:", r["messageId"])
            continue
        pending.append((r["messageId"], alert))

    # 웹훅(채널)별로 나눠서 전송
    by_webhook = {}
    for mid, alert in pending:
        by_webhook.setdefault(alert["webhook"], []).append((mid, alert))

    for url, items in by_webhook.items():
        for chunk in chunk_for_discord(items):
            try:
                status = send_discord([a for _, a in chunk], url)
                print("sent:", [a["title"] for _, a in chunk], status)
            except Exception as e:
                print("send error:", e)
                failures.extend(mid for mid, _ in chunk)

    # 실패한 메시지만 SQS가 다시 보내도록 알려줌
    return {"batchItemFailures": [{"itemIdentifier": mid} for mid in failures]}