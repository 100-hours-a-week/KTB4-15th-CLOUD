"""RDS 로그 파일 수집기 (db-log-tailer)

RDS API(DescribeDBLogFiles, DownloadDBLogFilePortion)로 DB 로그 파일을 이어 읽어 Alloy(Loki push API)로 보낸다.
- MySQL: MariaDB Audit Plugin 감사 로그 (audit/server_audit.log*) -> source="db-query"
- PostgreSQL: postgresql.log (log_statement=all + log_duration=on) -> 쿼리는 source="db-query",
  나머지(오류 등)는 PG_SEND_OTHER=true일 때 source="rds", log_group으로 보낸다
  같은 pid의 DETAIL(바인드 값)·duration·ERROR를 바로 앞 쿼리에 붙인다 (result=ok|error, duration_ms)
- 파일별 읽은 위치(Marker)를 STATE_FILE에 저장해 재시작해도 이어 읽는다.
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
def tail_target(rds, state, engine, instance, prefix):
    key_prefix = f"{instance}/"
    files = []
    for page in rds.get_paginator("describe_db_log_files").paginate(DBInstanceIdentifier=instance, FilenameContains=prefix):
        files += page["DescribeDBLogFiles"]
    files.sort(key=lambda f: f["LastWritten"])
    names = {f["LogFileName"] for f in files}
    init_key = key_prefix + "__init__"
    first_run = init_key not in state
    newest = files[-1]["LogFileName"] if files else None
    log_group = f"/aws/rds/instance/{instance}/postgresql"
    for f in files:
        name = f["LogFileName"]
        key = key_prefix + name
        st = state.get(key)
        if st is None:
            if first_run and not (engine == "mysql" or name == newest):
                # 처음 시작: PostgreSQL의 지난 시간 파일은 끝으로 건너뛴다 (과거 로그를 다시 보내지 않음)
                # MySQL 감사 파일과 PostgreSQL 현재 파일은 처음부터 읽는다 (DB 로깅을 켠 직후 쿼리를 놓치지 않게)
                resp = rds.download_db_log_file_portion(DBInstanceIdentifier=instance, LogFileName=name)
                while resp.get("AdditionalDataPending"):
                    resp = rds.download_db_log_file_portion(DBInstanceIdentifier=instance, LogFileName=name, Marker=resp["Marker"])
                state[key] = {"marker": resp["Marker"], "size": f["Size"]}
                continue
            st = state[key] = {"marker": "0", "size": 0}
        if f["Size"] < st.get("size", 0):
            # 같은 이름의 파일이 회전되어 작아졌다: 처음부터 다시 읽는다
            log(f"rotation detected {key}: size {st['size']} -> {f['Size']}")
            st["marker"] = "0"
        if f["Size"] == st.get("size") and st["marker"] != "0":
            continue
        marker = st["marker"]
        while True:
            resp = rds.download_db_log_file_portion(DBInstanceIdentifier=instance, LogFileName=name, Marker=marker)
            text = resp.get("LogFileData") or ""
            if text:
                entries = parse_mysql_audit(text) if engine == "mysql" else parse_pg(text, log_group)
                entries.sort(key=lambda e: e[0])
                for i in range(0, len(entries), PUSH_BATCH):
                    push(entries[i:i + PUSH_BATCH])
                if entries:
                    inc("lines", engine, len(entries))
                    setm("last_log_ts", engine, entries[-1][0].timestamp())
            marker = resp["Marker"]
            st["marker"] = marker
            save_state(state)
            if not resp.get("AdditionalDataPending"):
                break
        st["size"] = f["Size"]
        save_state(state)
    state[init_key] = True
    # RDS에서 사라진 파일의 위치 정보는 지운다
    for k in [k for k in state if k.startswith(key_prefix) and k != init_key and k[len(key_prefix):] not in names]:
        del state[k]
    save_state(state)


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
                setm("last_success", engine, time.time())
            except Exception as e:  # noqa: BLE001
                inc("errors", engine)
                log(f"{engine} {instance}: {e}")
        time.sleep(POLL_SECONDS)


if __name__ == "__main__":
    main()
