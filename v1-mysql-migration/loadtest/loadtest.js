// V1 MySQL 마이그레이션 부하 리허설용 k6 스크립트
// - 실제 사용자 경로(https://dev.lookddak.com → Spring → ProxySQL → RDS)로 API 부하를 준다.
// - DB 쓰기만 하고 AI를 부르지 않는 API만 사용한다. (채팅방은 만들기만 하고 스트림에 접속하지 않으면 AI 호출 없음)
// - VU 1개 = 테스트 계정 1개. refresh token rotation이 계정끼리 섞이지 않도록 VU 수를 계정 수로 고정한다.
//
// 실행 예: k6 run -e PASSWORD="$LT_PASSWORD" -e ACCOUNTS=10 -e RATE=20 -e DURATION=10m -e PRODUCT_ID=1 \
//            --summary-export results/summary.json --out csv=results/raw.csv.gz loadtest.js
//
// 요청 비율 (한 iteration = 요청 1개)
//   40% PATCH /api/v1/chat-rooms/{id}                 채팅방 제목 변경 (UPDATE 1건)
//   20% POST  /api/v1/products/{id}/purchase-link-clicks  클릭 수 +1 (카운터 검증)
//   10% POST  /api/v1/auth/refresh                     토큰 교체 (SELECT + UPDATE + INSERT)
//   15% GET   /api/v1/members/me                       읽기
//   15% GET   /api/v1/chat-rooms                       읽기

import http from 'k6/http';
import exec from 'k6/execution';
import { Counter } from 'k6/metrics';

const BASE = __ENV.BASE_URL || 'https://dev.lookddak.com';
const ACCOUNTS = parseInt(__ENV.ACCOUNTS || '10', 10);
// 테스트 계정 비밀번호는 저장소(public)에 두지 않고 실행할 때 넘긴다.
const PASSWORD = __ENV.PASSWORD;
const EMAIL_PREFIX = __ENV.EMAIL_PREFIX || 'loadtest';
const EMAIL_DOMAIN = __ENV.EMAIL_DOMAIN || 'example.com';
const PRODUCT_ID = __ENV.PRODUCT_ID || '1';
const RATE = parseInt(__ENV.RATE || '20', 10);
const DURATION = __ENV.DURATION || '10m';
// ProxySQL 전환 대기 한도(30초)보다 길게 잡아, 대기 중인 요청을 클라이언트가 먼저 끊지 않게 한다.
const HTTP_TIMEOUT = __ENV.HTTP_TIMEOUT || '60s';

const JSON_HEADERS = { 'Content-Type': 'application/json' };

export const options = {
  setupTimeout: '5m',
  // 기본값은 iteration마다 cookie jar를 비운다. 로그인 쿠키(refresh rotation 포함)를 VU 안에서 유지한다.
  noCookiesReset: true,
  scenarios: {
    mixed: {
      executor: 'constant-arrival-rate',
      rate: RATE,
      timeUnit: '1s',
      duration: DURATION,
      preAllocatedVUs: ACCOUNTS,
      maxVUs: ACCOUNTS,
    },
  },
  summaryTrendStats: ['avg', 'min', 'med', 'p(95)', 'p(99)', 'max'],
};

// 카운터 검증: 2xx를 받은 클릭 수와 DB click_count 증가량이 같아야 한다.
const clicksOk = new Counter('clicks_ok');
// 4xx·5xx·타임아웃: DB 반영 여부를 알 수 없는 클릭 (DB 증가량이 clicks_ok보다 크면 이쪽에서 반영된 것)
const clicksNotOk = new Counter('clicks_not_ok');
// 인증이 풀려 다시 로그인한 횟수 (refresh rotation이 꼬이면 증가)
const relogins = new Counter('relogins');
// API별 실패 (2xx 아님 또는 타임아웃)
const apiErrors = new Counter('api_errors');

function emailOf(i) {
  return `${EMAIL_PREFIX}${String(i).padStart(2, '0')}@${EMAIL_DOMAIN}`;
}

function login(email, jar) {
  const params = { headers: JSON_HEADERS, tags: { name: 'login' }, timeout: HTTP_TIMEOUT };
  if (jar) params.jar = jar;
  return http.post(`${BASE}/api/v1/auth/login`, JSON.stringify({ email, password: PASSWORD }), params);
}

// 계정이 없으면 만들고, 계정마다 채팅방을 하나 만든다. (제목 변경 대상)
export function setup() {
  if (!PASSWORD) {
    exec.test.abort('PASSWORD 환경 변수가 필요합니다 (-e PASSWORD=...)');
  }
  const rooms = [];
  for (let i = 1; i <= ACCOUNTS; i++) {
    const email = emailOf(i);
    const jar = new http.CookieJar();
    // 이미 있는 계정이면 가입은 실패하고 로그인으로 넘어간다.
    http.post(`${BASE}/api/v1/auth/signup`, JSON.stringify({ email, password: PASSWORD }),
      { headers: JSON_HEADERS, jar, tags: { name: 'setup' } });
    const res = login(email, jar);
    if (res.status !== 200) {
      exec.test.abort(`setup 로그인 실패: ${email} status=${res.status} body=${res.body}`);
    }
    const room = http.post(`${BASE}/api/v1/chat-rooms`,
      JSON.stringify({ content: '부하 테스트용 채팅방', sourceType: 'GENERAL' }),
      { headers: JSON_HEADERS, jar, tags: { name: 'setup' } });
    if (room.status !== 201) {
      exec.test.abort(`setup 채팅방 생성 실패: ${email} status=${room.status} body=${room.body}`);
    }
    rooms.push(room.json('data.chatRoomId'));
  }
  console.log(`setup 완료: 계정 ${ACCOUNTS}개, 채팅방 ${JSON.stringify(rooms)}, PRODUCT_ID=${PRODUCT_ID}`);
  return { rooms, startedAt: new Date().toISOString() };
}

// VU마다 처음 한 번 로그인 (VU 기본 cookie jar 사용)
let loggedIn = false;

function ensureLogin() {
  if (loggedIn) return;
  const res = login(emailOf(exec.vu.idInTest));
  if (res.status !== 200) {
    apiErrors.add(1, { name: 'login' });
    return;
  }
  loggedIn = true;
}

function call(name, method, url, body) {
  const params = { headers: JSON_HEADERS, tags: { name }, timeout: HTTP_TIMEOUT };
  let res = http.request(method, url, body ? JSON.stringify(body) : null, params);
  if (res.status === 401) {
    // access token 만료나 refresh rotation 실패 → 다시 로그인 후 한 번 재시도
    relogins.add(1, { name });
    loggedIn = false;
    ensureLogin();
    res = http.request(method, url, body ? JSON.stringify(body) : null, params);
  }
  if (res.status < 200 || res.status >= 300) {
    apiErrors.add(1, { name, status: String(res.status) });
  }
  return res;
}

export default function (data) {
  ensureLogin();
  if (!loggedIn) return;

  const roomId = data.rooms[exec.vu.idInTest - 1];
  const r = Math.random();

  if (r < 0.40) {
    call('chat_title', 'PATCH', `${BASE}/api/v1/chat-rooms/${roomId}`,
      { title: `lt-${exec.vu.idInTest}-${exec.vu.iterationInScenario % 100000}` });
  } else if (r < 0.60) {
    const res = call('product_click', 'POST', `${BASE}/api/v1/products/${PRODUCT_ID}/purchase-link-clicks`);
    if (res.status >= 200 && res.status < 300) {
      clicksOk.add(1);
    } else {
      clicksNotOk.add(1, { status: String(res.status) });
    }
  } else if (r < 0.70) {
    call('auth_refresh', 'POST', `${BASE}/api/v1/auth/refresh`);
  } else if (r < 0.85) {
    call('member_me', 'GET', `${BASE}/api/v1/members/me`);
  } else {
    call('chat_rooms', 'GET', `${BASE}/api/v1/chat-rooms`);
  }
}

export function teardown(data) {
  console.log(`부하 시작(setup 종료) ${data.startedAt}, 종료 ${new Date().toISOString()}`);
}
