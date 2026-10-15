-- PostgreSQL 마이그레이션 리허설에서 사용하는 pgbench 장부 기록 스크립트입니다.
-- pgbench가 이 파일을 한 번 실행할 때마다 migration_test_events에 장부 행 1개를 기록합니다.
-- 리허설이 끝난 후 run_id별 행 수와 event_id를 EC2/RDS에서 비교하면 유실·중복을 확인할 수 있습니다.
--
-- 실행할 때 반드시 전달해야 하는 pgbench 변수:
--   run_id              : 이번 리허설 실행을 구분하는 고유 이름
--   source_label         : 쓰기를 시작한 DB 방향을 표시하는 값(예: ec2, rds)
--   client_event_no      : 각 pgbench 클라이언트의 이벤트 순번 시작값. 실행할 때 0으로 전달
--   hold_sec             : INSERT 후 COMMIT 전까지 기다릴 초. 일반 부하는 0, 장기 트랜잭션은 30 등으로 지정
--
-- 일반 쓰기 예시 변수:      -D client_event_no=0 -D hold_sec=0
-- 장기 트랜잭션 예시 변수: -D client_event_no=0 -D hold_sec=30 -c 1 -t 1
--
-- pgbench의 client_id는 클라이언트마다 다르고 client_event_no는 각 클라이언트 안에서 계속 증가합니다.
-- 따라서 run_id + client_id + client_event_no 조합으로 DB 시퀀스 없이 고유 ID를 만들 수 있습니다.
-- PostgreSQL 논리 복제는 시퀀스 현재 값을 복제하지 않으므로 장부 ID에 DB 시퀀스를 사용하지 않습니다.
--
-- pgbench 문자열 변수는 ':run_id'처럼 문자열 리터럴 안에서 치환합니다.
-- SQL 문법과 로그 식별이 깨지지 않도록 run_id와 source_label에는 영문자, 숫자, 밑줄, 하이픈만 사용합니다.

-- 같은 pgbench 클라이언트가 다음 트랜잭션을 실행할 때 이전 값에서 1을 더합니다.
-- 실행 명령에서 모든 클라이언트의 시작값을 client_event_no=0으로 주입하므로 첫 이벤트 번호는 1입니다.
\set client_event_no :client_event_no + 1

-- INSERT와 선택적 대기 시간을 하나의 트랜잭션으로 묶습니다.
-- PgBouncer의 transaction 풀링에서는 BEGIN부터 COMMIT까지 같은 PostgreSQL 연결을 사용합니다.
BEGIN;

INSERT INTO public.migration_test_events (
    event_id,
    run_id,
    client_id,
    event_no,
    payload
)
VALUES (
    -- 사람이 읽을 수 있고 재현 가능한 고유 ID입니다.
    -- 예: run_id=r1, client_id=2, event_no=15이면 r1-2-15가 됩니다.
    concat(':run_id', '-', :client_id, '-', :client_event_no),

    -- 같은 리허설에서 생성된 행을 한 번에 조회·삭제할 수 있도록 실행 ID를 별도 컬럼에도 저장합니다.
    ':run_id',

    -- 어떤 pgbench 가상 클라이언트가 만든 행인지 기록합니다.
    :client_id,

    -- 해당 클라이언트가 이번 실행에서 몇 번째로 만든 행인지 기록합니다.
    :client_event_no,

    -- 장애 분석 시 행의 발생 방향과 실행 조건을 바로 확인할 수 있도록 부가 정보를 JSON으로 남깁니다.
    jsonb_build_object(
        'source', ':source_label',
        'client_id', :client_id,
        'event_no', :client_event_no,
        'hold_sec', :hold_sec
    )
);

-- 일반 부하는 hold_sec=0이므로 바로 COMMIT으로 넘어갑니다.
-- 사고 주입 리허설에서는 30처럼 양수를 주어 INSERT한 상태로 트랜잭션을 열어 둡니다.
-- 이때 PgBouncer PAUSE가 진행 중인 트랜잭션이 끝날 때까지 기다리는지 측정할 수 있습니다.
SELECT pg_sleep(:hold_sec);

-- COMMIT이 성공한 행만 최종 장부에 남습니다.
-- pgbench의 성공 트랜잭션 수와 이 테이블의 run_id별 행 수를 비교하는 기준점입니다.
COMMIT;
