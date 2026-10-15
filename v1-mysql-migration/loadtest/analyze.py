#!/usr/bin/env python3
"""k6 CSV 결과(raw.csv.gz)를 API별·초별로 요약하고, 정합성 검증용 기대값을 만든다.

사용법: python3 analyze.py results/raw.csv.gz [--slow-ms 1000] [--expected-out results/expected.txt]
- API별: 요청 수, 실패 수(2xx 아님·타임아웃), 응답 시간 p50·p99·최대
- 초별(UTC): 실패가 있거나 가장 느린 요청이 --slow-ms 이상인 초만 출력
  → cutover.sh 로그·observe.sh report 시각(UTC)과 맞춰 보면 전환 순간의 대기·에러를 확인할 수 있다.
- 정합성 기대값: 클릭 성공·실패 수, 채팅방별 마지막 성공 제목(그보다 나중에 실패한 제목 포함)
  → dev EC2에서 check-integrity.sh의 입력으로 쓴다.
"""
import argparse
import collections
import csv
import datetime
import gzip

SKIP = {"setup", "login"}


def pct(values, p):
    if not values:
        return 0.0
    values = sorted(values)
    k = max(0, min(len(values) - 1, int(round(p / 100 * len(values) + 0.5)) - 1))
    return values[k]


def utc(ts):
    return datetime.datetime.fromtimestamp(ts, datetime.timezone.utc).strftime("%H:%M:%S")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("csv")
    ap.add_argument("--slow-ms", type=float, default=1000)
    ap.add_argument("--expected-out", default=None)
    args = ap.parse_args()

    opener = gzip.open if args.csv.endswith(".gz") else open
    by_api = collections.defaultdict(list)          # name -> [duration]
    fail_api = collections.Counter()                # name -> 실패 수
    status_api = collections.Counter()              # (name, status) -> 수
    per_sec = collections.defaultdict(lambda: {"n": 0, "fail": 0, "max": 0.0, "fail_by": collections.Counter()})
    clicks = collections.Counter()                  # ok / not_ok
    titles = collections.defaultdict(list)          # room -> [(iter, title, ok)]

    with opener(args.csv, "rt") as f:
        for r in csv.DictReader(f):
            if r["metric_name"] == "http_reqs" and r["name"] in ("product_click", "chat_title"):
                ok = (r["status"] or "0").startswith("2")
                if r["name"] == "product_click":
                    clicks["ok" if ok else "not_ok"] += 1
                else:
                    tags = dict(kv.split("=", 1) for kv in (r.get("extra_tags") or "").split("&") if "=" in kv)
                    if "room" in tags and "title" in tags:
                        titles[tags["room"]].append((int(tags["title"].rsplit("-", 1)[1]), tags["title"], ok))
                continue
            if r["metric_name"] != "http_req_duration" or r["name"] in SKIP:
                continue
            name = r["name"]
            dur = float(r["metric_value"])
            status = r["status"] or "0"
            ts = int(float(r["timestamp"]))
            failed = not status.startswith("2")
            by_api[name].append(dur)
            status_api[(name, status)] += 1
            s = per_sec[ts]
            s["n"] += 1
            s["max"] = max(s["max"], dur)
            if failed:
                fail_api[name] += 1
                s["fail"] += 1
                s["fail_by"][f"{name}:{status}"] += 1

    print("== API별 (응답 시간 ms)")
    print(f"{'api':<15}{'요청':>8}{'실패':>6}{'p50':>9}{'p99':>9}{'max':>10}")
    total = fails = 0
    for name in sorted(by_api):
        d = by_api[name]
        total += len(d)
        fails += fail_api[name]
        print(f"{name:<15}{len(d):>8}{fail_api[name]:>6}{pct(d, 50):>9.0f}{pct(d, 99):>9.0f}{max(d):>10.0f}")
    print(f"{'합계':<15}{total:>8}{fails:>6}")

    print("\n== 상태 코드")
    for (name, status), n in sorted(status_api.items()):
        print(f"{name:<15}{status:>5}{n:>8}")

    print(f"\n== 초별 (UTC, 실패가 있거나 최대 응답 >= {args.slow_ms:.0f}ms인 초만, 시각은 응답 완료 기준)")
    print(f"{'시각':<10}{'요청':>6}{'실패':>6}{'최대ms':>9}  실패 내역")
    shown = 0
    for ts in sorted(per_sec):
        s = per_sec[ts]
        if s["fail"] or s["max"] >= args.slow_ms:
            detail = ", ".join(f"{k}x{v}" for k, v in s["fail_by"].items())
            print(f"{utc(ts):<10}{s['n']:>6}{s['fail']:>6}{s['max']:>9.0f}  {detail}")
            shown += 1
    if not shown:
        print("(해당 없음)")
    if per_sec:
        print(f"\n측정 구간: {utc(min(per_sec))} ~ {utc(max(per_sec))} UTC")

    # 정합성 기대값
    lines = [f"CLICKS_OK {clicks['ok']}", f"CLICKS_NOT_OK {clicks['not_ok']}"]
    for room in sorted(titles, key=int):
        reqs = sorted(titles[room])
        ok_reqs = [t for t in reqs if t[2]]
        last_ok = ok_reqs[-1] if ok_reqs else None
        later_failed = [t[1] for t in reqs if not t[2] and (last_ok is None or t[0] > last_ok[0])]
        lines.append(f"ROOM {room} {last_ok[1] if last_ok else '-'} {','.join(later_failed) or '-'}")
    print("\n== 정합성 기대값 (dev EC2에서 expected.txt로 저장 → check-integrity.sh 입력)")
    print("\n".join(lines))
    print("   ROOM <채팅방 id> <마지막 성공 제목> <그보다 나중에 실패한 제목들: DB에 반영됐으면 '결과 불명 반영'>")
    if args.expected_out:
        with open(args.expected_out, "w") as f:
            f.write("\n".join(lines) + "\n")
        print(f"(저장: {args.expected_out})")


if __name__ == "__main__":
    main()
