"""RDS 로그 파일 수집기 (db-log-tailer)

RDS API(DescribeDBLogFiles, DownloadDBLogFilePortion)로 DB 로그 파일을 이어 읽어 Alloy(Loki push API)로 보낸다.
- MySQL: MariaDB Audit Plugin 감사 로그 (audit/server_audit.log*) -> source="db-query"
- MySQL: 오류 로그(error/), 슬로우 쿼리 로그(slowquery/) -> source="rds",
  log_group=/aws/rds/instance/<id>/{error,slowquery} (예전 CloudWatch 경로와 같은 레이블)
- PostgreSQL: postgresql.log (log_statement=all + log_duration=on) -> 쿼리는 source="db-query",
  나머지(오류 등)는 PG_SEND_OTHER=true일 때 source="rds", log_group으로 보낸다
  같은 pid의 DETAIL(바인드 값)·duration·ERROR를 바로 앞 쿼리에 붙인다 (result=ok|error, duration_ms)
- 파일별 읽은 위치(Marker)를 STATE_FILE에 저장해 재시작해도 이어 읽는다.
- MySQL 로그 회전: 현재 파일(server_audit.log, mysql-error-running.log, mysql-slowquery.log)만 이어 읽는다.
  회전되면 마지막으로 읽은 위치 이후의 남은 부분을 회전된 파일에서 마저 읽는다 (Marker "0:<offset>").
  - error·slowquery: 1시간마다 <이름>.YYYY-MM-DD.H 로 회전 (새 회전 파일이 보이면 회전)
  - audit: 100MB마다 <이름>.01 로 회전, 이전 파일은 .02… 로 밀린다 (현재 파일이 작아지면 회전)
- /metrics: Prometheus 지표 (마지막 성공 시각, 보낸 줄 수, 오류 수, 지연)
"""
import json
import os
import re
import sys
import threading
import time
import urllib.request
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, HTTPServer

REGION = os.environ.get("AWS_REGION", "ap-northeast-2")
# Alloy(:3500)로 보내면 Alloy가 env 레이블을 붙인다. Loki로 바로 보낼 때만 ENV_LABEL을 준다.
ENV = os.environ.get("ENV_LABEL", "")
LOKI_URL = os.environ.get("LOKI_URL", "http://alloy:3500/loki/api/v1/push")
STATE_FILE = os.environ.get("STATE_FILE", "/state/positions.json")
POLL_SECONDS = int(os.environ.get("POLL_SECONDS", "5"))
METRICS_PORT = int(os.environ.get("METRICS_PORT", "9200"))
# "engine:instance_id:file_prefix,..."
TARGETS = [t.split(":") for t in os.environ.get("TARGETS", "").split(",") if t]
# PostgreSQL 쿼리 외 로그(오류 등)도 보낼지 (source="rds", 기존 CloudWatch 경로와 같은 레이블)
PG_SEND_OTHER = os.environ.get("PG_SEND_OTHER", "false").lower() == "true"
EXCLUDE_USERS = set(u for u in os.environ.get("EXCLUDE_USERS", "rdsadmin,exporter").split(",") if u)
PUSH_BATCH = 1000

METRICS = {"lines": {}, "errors": {}, "last_success": {}, "last_log_ts": {}}
LOCK = threading.Lock()


def log(msg):
    print(f"{datetime.now(timezone.utc).isoformat()} {msg}", flush=True)


def inc(name, key, n=1):
    with LOCK:
        METRICS[name][key] = METRICS[name].get(key, 0) + n


def setm(name, key, v):
    with LOCK:
        METRICS[name][key] = v


# ---------------------------------------------------------------- parsers
MYSQL_UNESCAPE = {"n": "\n", "r": "\r", "t": "\t", "\\": "\\", "'": "'", "0": "\0"}


def split_mysql_audit_line(line):
    """감사 로그 한 줄을 필드로 나눈다.
    object(쿼리) 필드만 작은따옴표로 감싸고, 안의 ' 줄바꿈 등은 \\' \\n 처럼 백슬래시로 이스케이프된다."""
    fields, buf, i, n = [], [], 0, len(line)
    while i < n:
        c = line[i]
        if c == "'" and not buf:
            i += 1
            while i < n:
                c = line[i]
                if c == "\\" and i + 1 < n:
                    buf.append(MYSQL_UNESCAPE.get(line[i + 1], line[i + 1]))
                    i += 2
                    continue
                if c == "'":
                    i += 1
                    break
                buf.append(c)
                i += 1
            continue
        if c == ",":
            fields.append("".join(buf))
            buf = []
        else:
            buf.append(c)
        i += 1
    fields.append("".join(buf))
    return fields


def parse_mysql_audit(text):
    """MariaDB Audit Plugin CSV:
    timestamp,serverhost,username,host,connectionid,queryid,operation,database,object,retcode[,connection_type]"""
    out = []
    for raw in text.splitlines():
        row = split_mysql_audit_line(raw)
        if len(row) < 10:
            continue
        ts_s, _server, user, host, conn, qid, op, db, obj, ret = row[:10]
        if user in EXCLUDE_USERS:
            continue
        try:
            ts = datetime.strptime(ts_s, "%Y%m%d %H:%M:%S").replace(tzinfo=timezone.utc)
        except ValueError:
            continue
        line = obj if op == "QUERY" else f"{op} {obj}".strip()
        meta = {"connection_id": conn, "query_id": qid, "client_host": host, "operation": op,
                "database": db, "retcode": ret}
        if len(row) > 10:
            meta["connection_type"] = row[10]
        out.append((ts, {"source": "db-query", "db": "mysql", "db_user": user or "unknown"}, line, meta))
    return out


# 2026-10-19T02:16:34.072141Z 0 [System] [MY-010931] [Server] message
MYSQL_ERROR_LINE = re.compile(
    r"^(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2})(?:\.\d+)?Z\s+(\d+)\s+\[(\w+)\]\s+\[([^\]]*)\]\s+\[([^\]]*)\]\s?(.*)$")
# 감사 플러그인이 오류 로그에 남기는 줄: 261023 13:59:41 server_audit: ...
MYSQL_PLUGIN_LINE = re.compile(r"^(\d{6} \d{2}:\d{2}:\d{2}) (.*)$")


def parse_mysql_error(text, log_group):
    """MySQL 오류 로그. 한 줄 = 한 건. 시각이 없는 줄([AWS_QPC_INFO] 등)은 바로 앞 시각으로 보낸다."""
    out = []
    last_ts = None
    for raw in text.splitlines():
        if not raw.strip():
            continue
        meta = {}
        m = MYSQL_ERROR_LINE.match(raw)
        p = MYSQL_PLUGIN_LINE.match(raw) if not m else None
        if m:
            last_ts = datetime.strptime(m.group(1), "%Y-%m-%dT%H:%M:%S").replace(tzinfo=timezone.utc)
            meta = {"thread": m.group(2), "level": m.group(3), "code": m.group(4), "subsystem": m.group(5)}
        elif p:
            try:
                last_ts = datetime.strptime(p.group(1), "%y%m%d %H:%M:%S").replace(tzinfo=timezone.utc)
            except ValueError:
                pass
        if last_ts is None:
            continue
        out.append((last_ts, {"source": "rds", "log_group": log_group}, raw, meta))
    return out


MYSQL_SLOW_TIME = re.compile(r"^# Time: (\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2})")
MYSQL_SLOW_USER = re.compile(r"^# User@Host: ([^\[]*)\[[^\]]*\] @ ([^\[]*)\[([^\]]*)\]\s+Id:\s+(\d+)")
MYSQL_SLOW_STATS = re.compile(
    r"^# Query_time: ([0-9.]+)\s+Lock_time: ([0-9.]+)\s+Rows_sent: (\d+)\s+Rows_examined: (\d+)")
# 서버 시작·회전 때 파일 앞에 붙는 머리말
MYSQL_SLOW_HEADER = ("/rdsdbbin/", "Tcp port:", "Time                 Id Command")


def parse_mysql_slow(text, log_group):
    """MySQL 슬로우 쿼리 로그. "# Time:"부터 다음 "# Time:" 전까지 = 한 건 (원문 그대로)."""
    out = []
    cur = None

    def flush():
        if cur and cur["user"] not in EXCLUDE_USERS:
            out.append((cur["ts"], {"source": "rds", "log_group": log_group}, "\n".join(cur["lines"]), cur["meta"]))

    for raw in text.splitlines():
        if raw.startswith(MYSQL_SLOW_HEADER):
            flush()
            cur = None
            continue
        t = MYSQL_SLOW_TIME.match(raw)
        if t:
            flush()
            cur = {"ts": datetime.strptime(t.group(1), "%Y-%m-%dT%H:%M:%S").replace(tzinfo=timezone.utc),
                   "lines": [raw], "meta": {}, "user": ""}
            continue
        if cur is None:
            continue
        cur["lines"].append(raw)
        u = MYSQL_SLOW_USER.match(raw)
        if u:
            cur["user"] = u.group(1).strip()
            cur["meta"].update(db_user=cur["user"] or "unknown", client_host=u.group(3) or u.group(2).strip(),
                               connection_id=u.group(4))
            continue
        q = MYSQL_SLOW_STATS.match(raw)
        if q:
            cur["meta"].update(query_time=q.group(1), lock_time=q.group(2), rows_sent=q.group(3),
                               rows_examined=q.group(4))
    flush()
    return out


# RDS 기본 log_line_prefix: %t:%r:%u@%d:[%p]:
PG_PREFIX = re.compile(
    r"^(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}(?:\.\d+)? UTC):([^:]*):([^@]*)@([^:]*):\[(\d+)\]:([A-Z]+):\s{1,2}(.*)$")
PG_DURATION = re.compile(r"^duration: ([0-9.]+) ms$")
PG_QUERY = re.compile(r"^(statement|execute [^:]*|duration: [^ ]+ ms\s+(?:statement|execute [^:]*)):\s?(.*)$", re.S)


def parse_pg(text, log_group):
    """접두어가 있는 줄 = 새 레코드, 접두어 없는 줄(탭 들여쓰기) = 앞 레코드에 이어 붙임.
    DETAIL: parameters 는 같은 pid의 바로 앞 쿼리에 합친다."""
    recs = []
    for raw in text.splitlines():
        m = PG_PREFIX.match(raw)
        if m:
            recs.append(list(m.groups()))
        elif recs:
            recs[-1][6] += "\n" + raw
    out = []
    last_query_by_pid = {}
    for ts_s, host, user, db, pid, level, msg in recs:
        ts = datetime.strptime(ts_s.split(".")[0], "%Y-%m-%d %H:%M:%S UTC").replace(tzinfo=timezone.utc)
        if level == "DETAIL" and msg.startswith("parameters:") and pid in last_query_by_pid:
            q = last_query_by_pid[pid]
            q[2] = f"{q[2]}\n{msg}"
            continue
        dm = PG_DURATION.match(msg) if level == "LOG" else None
        if dm:
            # 앞 쿼리가 이전 읽기에서 이미 전송된 경우 duration 줄은 버린다 (result 없이 남음)
            if pid in last_query_by_pid:
                q = last_query_by_pid.pop(pid)
                q[3]["duration_ms"] = dm.group(1)
                q[3]["result"] = "ok"
            continue
        if level in ("ERROR", "FATAL") and pid in last_query_by_pid:
            q = last_query_by_pid.pop(pid)
            q[3]["result"] = "error"
        meta = {"client_host": host, "pid": pid, "database": db, "level": level}
        qm = PG_QUERY.match(msg) if level == "LOG" else None
        if qm:
            if user in EXCLUDE_USERS:
                continue
            meta["kind"] = qm.group(1).split(":")[0].strip()
            rec = [ts, {"source": "db-query", "db": "postgresql", "db_user": user or "unknown"}, qm.group(2), meta]
            last_query_by_pid[pid] = rec
        else:
            # 제외 사용자(exporter 등)의 일반 로그·바인드 값(DETAIL)은 버리고, 오류·경고만 남긴다
            if not PG_SEND_OTHER or (user in EXCLUDE_USERS and level not in ("WARNING", "ERROR", "FATAL", "PANIC")):
                continue
            rec = [ts, {"source": "rds", "log_group": log_group}, f"{level}: {msg}", meta]
        out.append(rec)
    return [tuple(r) for r in out]


# ---------------------------------------------------------------- loki
def push(entries):
    streams = {}
    for ts, labels, line, meta in entries:
        labels = dict(labels, env=ENV) if ENV else dict(labels)
        key = tuple(sorted(labels.items()))
        streams.setdefault(key, []).append([str(int(ts.timestamp() * 1e9)), line, {k: str(v) for k, v in meta.items() if v != ""}])
    body = {"streams": [{"stream": dict(k), "values": sorted(v, key=lambda x: int(x[0]))} for k, v in streams.items()]}
    data = json.dumps(body).encode()
    for attempt in range(5):
        try:
            req = urllib.request.Request(LOKI_URL, data=data, headers={"Content-Type": "application/json"})
            with urllib.request.urlopen(req, timeout=15) as r:
                if r.status in (200, 204):
                    return
        except Exception as e:  # noqa: BLE001
            log(f"loki push failed (attempt {attempt + 1}): {e}")
            time.sleep(2 ** attempt)
    raise RuntimeError("loki push failed")


# ---------------------------------------------------------------- state
def load_state():
    try:
        with open(STATE_FILE) as f:
            return json.load(f)
    except FileNotFoundError:
        return {}


def save_state(state):
    tmp = STATE_FILE + ".tmp"
    with open(tmp, "w") as f:
        json.dump(state, f)
    os.replace(tmp, STATE_FILE)


# ---------------------------------------------------------------- tail
# MySQL 회전 파일 이름: <현재 파일>.YYYY-MM-DD.H (error, slowquery) / <현재 파일>.NN (audit)
MYSQL_ROTATED_HOURLY = re.compile(r"^(?P<base>.+)\.(?P<date>\d{4}-\d{2}-\d{2})\.(?P<hour>\d{1,2})$")
MYSQL_ROTATED_NUMBERED = re.compile(r"^(?P<base>.+)\.(?P<num>\d{2})$")


def rotated_base(name):
    m = MYSQL_ROTATED_HOURLY.match(name) or MYSQL_ROTATED_NUMBERED.match(name)
    return m.group("base") if m else None


def rotation_order(name):
    """회전 파일을 오래된 것부터 정렬하는 키"""
    m = MYSQL_ROTATED_HOURLY.match(name)
    if m:
        return (m.group("date"), int(m.group("hour")))
    m = MYSQL_ROTATED_NUMBERED.match(name)
    return ("", -int(m.group("num"))) if m else ("", 0)


def marker_offset(marker):
    """RDS Marker "<회전 시각>:<바이트 위치>"에서 위치만 꺼낸다"""
    try:
        return int(str(marker).rsplit(":", 1)[-1])
    except ValueError:
        return 0


def target_kind(engine, prefix):
    return "postgresql" if engine == "postgresql" else prefix.strip("/").split("/")[0]


def metric_key(engine, kind):
    # 기존 지표 레이블 유지: MySQL 감사 로그 = "mysql", PostgreSQL = "postgresql"
    return engine if kind in ("audit", "postgresql") else f"{engine}_{kind}"


def parse_entries(engine, kind, instance, text):
    log_group = f"/aws/rds/instance/{instance}/{kind}"
    if kind == "postgresql":
        return parse_pg(text, log_group)
    if kind == "audit":
        return parse_mysql_audit(text)
    if kind == "error":
        return parse_mysql_error(text, log_group)
    if kind == "slowquery":
        return parse_mysql_slow(text, log_group)
    raise ValueError(f"unknown log kind: {kind}")


def read_file(rds, state, st, engine, kind, instance, name, marker):
    """marker부터 파일 끝까지 읽어 보낸다. st가 있으면 읽을 때마다 위치를 저장한다. 마지막 marker를 돌려준다."""
    key = metric_key(engine, kind)
    while True:
        resp = rds.download_db_log_file_portion(DBInstanceIdentifier=instance, LogFileName=name, Marker=marker)
        text = resp.get("LogFileData") or ""
        if text:
            entries = parse_entries(engine, kind, instance, text)
            entries.sort(key=lambda e: e[0])
            for i in range(0, len(entries), PUSH_BATCH):
                push(entries[i:i + PUSH_BATCH])
            if entries:
                inc("lines", key, len(entries))
                # error·slowquery는 드물게 쌓여 "마지막 로그 시각"이 지연처럼 보이므로 감사·PG 로그만 기록한다
                if kind in ("audit", "postgresql"):
                    setm("last_log_ts", key, entries[-1][0].timestamp())
        marker = resp["Marker"]
        if st is not None:
            st["marker"] = marker
            save_state(state)
        if not resp.get("AdditionalDataPending"):
            return marker


def list_files(rds, instance, prefix):
    files = []
    for page in rds.get_paginator("describe_db_log_files").paginate(DBInstanceIdentifier=instance, FilenameContains=prefix):
        files += page["DescribeDBLogFiles"]
    return files


def tail_postgresql(rds, state, instance, prefix):
    """PostgreSQL: 1시간마다 새 이름(postgresql.log.YYYY-MM-DD-HH)으로 쓰므로 파일별로 이어 읽는다."""
    key_prefix = f"{instance}/"
    files = sorted(list_files(rds, instance, prefix), key=lambda f: f["LastWritten"])
    names = {f["LogFileName"] for f in files}
    init_key = key_prefix + "__init__"
    first_run = init_key not in state
    newest = files[-1]["LogFileName"] if files else None
    for f in files:
        name = f["LogFileName"]
        key = key_prefix + name
        st = state.get(key)
        if st is None:
            if first_run and name != newest:
                # 처음 시작: 지난 시간 파일은 끝으로 건너뛴다 (과거 로그를 다시 보내지 않음)
                resp = rds.download_db_log_file_portion(DBInstanceIdentifier=instance, LogFileName=name)
                while resp.get("AdditionalDataPending"):
                    resp = rds.download_db_log_file_portion(DBInstanceIdentifier=instance, LogFileName=name, Marker=resp["Marker"])
                state[key] = {"marker": resp["Marker"], "size": f["Size"]}
                continue
            st = state[key] = {"marker": "0", "size": 0}
        if f["Size"] < st.get("size", 0):
            log(f"rotation detected {key}: size {st['size']} -> {f['Size']}")
            st["marker"] = "0"
        if f["Size"] == st.get("size") and st["marker"] != "0":
            continue
        read_file(rds, state, st, "postgresql", "postgresql", instance, name, st["marker"])
        st["size"] = f["Size"]
        save_state(state)
    state[init_key] = True
    for k in [k for k in state if k.startswith(key_prefix) and k != init_key and k[len(key_prefix):] not in names]:
        del state[k]
    save_state(state)


def tail_mysql(rds, state, instance, prefix):
    """MySQL: 현재 파일만 이어 읽고, 회전되면 남은 부분을 회전된 파일에서 마저 읽는다."""
    kind = target_kind("mysql", prefix)
    key_prefix = f"{instance}/"
    target_prefix = key_prefix + prefix
    init_key = f"{key_prefix}__init__/{prefix}"
    # 이 대상의 파일 위치가 하나라도 있으면 처음이 아니다 (예전 버전이 남긴 감사 로그 위치 포함)
    first_run = init_key not in state and not any(k.startswith(target_prefix) for k in state)
    files = list_files(rds, instance, prefix)
    names = {f["LogFileName"] for f in files}
    current = {f["LogFileName"]: f for f in files if rotated_base(f["LogFileName"]) is None}
    rotated = {}
    for f in files:
        base = rotated_base(f["LogFileName"])
        if base is not None:
            rotated.setdefault(base, []).append(f["LogFileName"])

    for name in sorted(current):
        f = current[name]
        key = key_prefix + name
        st = state.get(key)
        if st is None:
            st = state[key] = {"marker": "0", "size": 0}
        unseen = sorted((r for r in rotated.get(name, []) if key_prefix + r not in state), key=rotation_order)
        shrunk = f["Size"] < st.get("size", 0)

        if first_run:
            # 처음 시작: 지난 회전 파일은 보내지 않고 현재 파일만 처음부터 읽는다
            pass
        elif unseen or shrunk:
            offset = marker_offset(st["marker"])
            if unseen:
                # 시간 단위 회전: 가장 오래된 새 회전 파일 = 방금까지 읽던 파일. 그 뒤 것은 통째로 읽는다
                cont, rest = unseen[0], unseen[1:]
            else:
                # 번호 회전(audit): 방금까지 읽던 파일은 .01
                cont, rest = (name + ".01" if name + ".01" in names else None), []
            log(f"rotation {key}: continue {cont} from offset {offset}, then {len(rest)} file(s)")
            if cont:
                read_file(rds, state, None, "mysql", kind, instance, cont, f"0:{offset}")
            for r in rest:
                read_file(rds, state, None, "mysql", kind, instance, r, "0")
            st["marker"], st["size"] = "0", 0
            save_state(state)

        # 회전 파일은 이어 읽기에서만 쓰고, 본 것으로 표시한다
        for r in rotated.get(name, []):
            state.setdefault(key_prefix + r, {"seen": True})

        if f["Size"] == st.get("size") and st["marker"] != "0":
            continue
        read_file(rds, state, st, "mysql", kind, instance, name, st["marker"])
        st["size"] = f["Size"]
        save_state(state)

    state[init_key] = True
    for k in [k for k in state if k.startswith(target_prefix) and k[len(key_prefix):] not in names]:
        del state[k]
    save_state(state)


def tail_target(rds, state, engine, instance, prefix):
    if engine == "postgresql":
        tail_postgresql(rds, state, instance, prefix)
    else:
        tail_mysql(rds, state, instance, prefix)


# ---------------------------------------------------------------- metrics
class Metrics(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path != "/metrics":
            self.send_response(404)
            self.end_headers()
            return
        now = time.time()
        lines = []
        with LOCK:
            lines.append("# TYPE db_log_tailer_lines_total counter")
            lines += [f'db_log_tailer_lines_total{{engine="{k}"}} {v}' for k, v in METRICS["lines"].items()]
            lines.append("# TYPE db_log_tailer_errors_total counter")
            lines += [f'db_log_tailer_errors_total{{engine="{k}"}} {v}' for k, v in METRICS["errors"].items()]
            lines.append("# TYPE db_log_tailer_last_success_timestamp_seconds gauge")
            lines += [f'db_log_tailer_last_success_timestamp_seconds{{engine="{k}"}} {v}' for k, v in METRICS["last_success"].items()]
            lines.append("# TYPE db_log_tailer_last_log_timestamp_seconds gauge")
            lines += [f'db_log_tailer_last_log_timestamp_seconds{{engine="{k}"}} {v}' for k, v in METRICS["last_log_ts"].items()]
        body = ("\n".join(lines) + "\n").encode()
        self.send_response(200)
        self.send_header("Content-Type", "text/plain; version=0.0.4")
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *_):
        pass


def main():
    import boto3  # 이미지 안에만 있다 (파서 테스트는 boto3 없이 가능)
    if not TARGETS:
        sys.exit("TARGETS is empty")
    threading.Thread(target=HTTPServer(("0.0.0.0", METRICS_PORT), Metrics).serve_forever, daemon=True).start()
    rds = boto3.client("rds", region_name=REGION)
    state = load_state()
    log(f"start targets={TARGETS}")
    while True:
        for engine, instance, prefix in TARGETS:
            try:
                tail_target(rds, state, engine, instance, prefix)
                setm("last_success", metric_key(engine, target_kind(engine, prefix)), time.time())
            except Exception as e:  # noqa: BLE001
                inc("errors", metric_key(engine, target_kind(engine, prefix)))
                log(f"{engine} {instance} {prefix}: {e}")
        time.sleep(POLL_SECONDS)


if __name__ == "__main__":
    main()
