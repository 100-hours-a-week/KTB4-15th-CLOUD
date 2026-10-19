// PostgreSQL 전환 중 V1 Prod 읽기 요청이 끊기지 않는지 10 RPS로 관찰한다.
// 기존 운영 테스트 계정으로 한 번 로그인하고 응답 쿠키를 읽기 요청에 자동 사용한다.

import http from 'k6/http';
import exec from 'k6/execution';
import { check } from 'k6';
import { Counter } from 'k6/metrics';

const BASE_URL = (__ENV.BASE_URL || 'https://lookddak.com').replace(/\/$/, '');
const READ_PATH = __ENV.READ_PATH || '/api/v1/chat-rooms';
const RATE = Number.parseInt(__ENV.RATE || '10', 10);
const DURATION = __ENV.DURATION || '10m';
const HTTP_TIMEOUT = __ENV.HTTP_TIMEOUT || '10s';
const EXPECTED_STATUS = Number.parseInt(__ENV.EXPECTED_STATUS || '200', 10);
const EXPECTED_BODY_TEXT = __ENV.EXPECTED_BODY_TEXT || '';
const RUN_ID = __ENV.RUN_ID || `prod-read-${Date.now()}`;
const P99_MS = Number.parseInt(__ENV.P99_MS || '5000', 10);
const PREALLOCATED_VUS = Number.parseInt(__ENV.PREALLOCATED_VUS || String(Math.max(20, RATE)), 10);
const MAX_VUS = Number.parseInt(__ENV.MAX_VUS || String(Math.max(40, RATE * 2)), 10);
const CREDENTIALS_FILE = __ENV.CREDENTIALS_FILE || '/run/secrets/k6-credentials';
const CREDENTIALS = JSON.parse(open(CREDENTIALS_FILE));

if (!READ_PATH.startsWith('/')) {
  exec.test.abort('READ_PATH는 /로 시작해야 합니다.');
}
if (!Number.isInteger(RATE) || RATE !== 10) {
  exec.test.abort('운영 전환 검증 RATE는 반드시 10이어야 합니다.');
}
if (!Number.isInteger(PREALLOCATED_VUS) || !Number.isInteger(MAX_VUS) || PREALLOCATED_VUS <= 0 || MAX_VUS < PREALLOCATED_VUS) {
  exec.test.abort('PREALLOCATED_VUS와 MAX_VUS 설정을 확인하세요.');
}
if (!CREDENTIALS || typeof CREDENTIALS.email !== 'string' || !CREDENTIALS.email.trim()
  || typeof CREDENTIALS.password !== 'string' || !CREDENTIALS.password) {
  exec.test.abort('운영 테스트 계정 email/password를 확인하세요.');
}

export const options = {
  scenarios: {
    prod_read_observer: {
      executor: 'constant-arrival-rate',
      rate: RATE,
      timeUnit: '1s',
      duration: DURATION,
      preAllocatedVUs: PREALLOCATED_VUS,
      maxVUs: MAX_VUS,
      gracefulStop: '5s',
    },
  },
  thresholds: {
    dropped_iterations: ['count==0'],
    'checks{endpoint:prod_read}': ['rate==1'],
    'http_req_failed{endpoint:prod_read}': ['rate==0'],
    'http_req_duration{endpoint:prod_read}': [`p(99)<${P99_MS}`],
    'server_errors{endpoint:prod_read}': ['count==0'],
    'transport_errors{endpoint:prod_read}': ['count==0'],
  },
  summaryTrendStats: ['avg', 'min', 'med', 'p(95)', 'p(99)', 'max'],
};

const serverErrors = new Counter('server_errors');
const transportErrors = new Counter('transport_errors');

function cookieHeader(response) {
  const parts = [];
  for (const [name, values] of Object.entries(response.cookies || {})) {
    if (values && values.length && values[0].value) parts.push(`${name}=${values[0].value}`);
  }
  return parts.join('; ');
}

export function setup() {
  const response = http.post(
    `${BASE_URL}/api/v1/auth/login`,
    JSON.stringify({ email: CREDENTIALS.email.trim(), password: CREDENTIALS.password }),
    {
      headers: { Accept: 'application/json', 'Content-Type': 'application/json' },
      timeout: HTTP_TIMEOUT,
      redirects: 0,
      tags: { endpoint: 'auth', name: 'auth_login' },
    },
  );
  const cookie = cookieHeader(response);
  if (response.status !== 200 || !cookie.includes('accessToken=') || !cookie.includes('refreshToken=')) {
    exec.test.abort(`운영 테스트 계정 로그인 실패: status=${response.status}`);
  }
  return { cookie };
}

function requestHeaders(requestId, cookie) {
  return { Accept: 'application/json', Cookie: cookie, 'X-Request-ID': requestId };
}

export default function (data) {
  const requestId = `pg-cutover-${RUN_ID}-${exec.vu.idInTest}-${exec.scenario.iterationInTest}-${Date.now()}`;
  const response = http.get(`${BASE_URL}${READ_PATH}`, {
    headers: requestHeaders(requestId, data.cookie),
    timeout: HTTP_TIMEOUT,
    redirects: 0,
    tags: { endpoint: 'prod_read', name: 'prod_read' },
  });

  if (response.status >= 500) {
    serverErrors.add(1, { endpoint: 'prod_read', status: String(response.status) });
  }
  if (response.status === 0 || response.error_code) {
    transportErrors.add(1, { endpoint: 'prod_read', error_code: String(response.error_code || 0) });
  }

  const passed = check(response, {
    [`status is ${EXPECTED_STATUS}`]: (res) => res.status === EXPECTED_STATUS,
    'expected response body is present': (res) => EXPECTED_BODY_TEXT === '' || String(res.body || '').includes(EXPECTED_BODY_TEXT),
  }, { endpoint: 'prod_read' });

  if (!passed) {
    console.error(JSON.stringify({
      at: new Date().toISOString(),
      request_id: requestId,
      status: response.status,
      error: response.error || '',
      error_code: response.error_code || 0,
    }));
  }
}
