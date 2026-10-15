// User-facing availability observer. The default GET is cost-free and passes through
// Nginx and Spring. It does not query the FastAPI PostgreSQL database directly:
// the current FastAPI OpenAPI exposes only GET /health and Nginx has no FastAPI route.
// Use READ_PATH/EXPECTED_BODY_TEXT for a confirmed read scenario when one is available.

import http from 'k6/http';
import exec from 'k6/execution';
import { check, sleep } from 'k6';
import { Counter } from 'k6/metrics';

const BASE_URL = (__ENV.BASE_URL || 'https://dev.lookddak.com').replace(/\/$/, '');
const READ_PATH = __ENV.READ_PATH || '/api/v1/chat-rooms';
const RATE = Number.parseInt(__ENV.RATE || '10', 10);
const DURATION = __ENV.DURATION || '5m';
const HTTP_TIMEOUT = __ENV.HTTP_TIMEOUT || '10s';
const EXPECTED_STATUS = Number.parseInt(__ENV.EXPECTED_STATUS || '200', 10);
const EXPECTED_BODY_TEXT = __ENV.EXPECTED_BODY_TEXT || '';
const RUN_ID = __ENV.RUN_ID || `read-${Date.now()}`;
const MAX_FAILURE_RATE = Number.parseFloat(__ENV.MAX_FAILURE_RATE || '0');
const P99_MS = Number.parseInt(__ENV.P99_MS || '5000', 10);
const PREALLOCATED_VUS = Number.parseInt(__ENV.PREALLOCATED_VUS || String(Math.max(10, RATE)), 10);
const MAX_VUS = Number.parseInt(__ENV.MAX_VUS || String(Math.max(20, RATE * 2)), 10);
const TEST_PASSWORD = __ENV.TEST_PASSWORD || '';
const TEST_EMAIL_PREFIX = __ENV.TEST_EMAIL_PREFIX || `pg-rehearsal-${RUN_ID}-`;
const TEST_EMAIL_DOMAIN = __ENV.TEST_EMAIL_DOMAIN || 'example.com';
const TOKEN_REFRESH_INTERVAL_MS = Number.parseInt(__ENV.TOKEN_REFRESH_INTERVAL_MS || '45000', 10);
const JSON_HEADERS = { 'Content-Type': 'application/json' };

if (!READ_PATH.startsWith('/')) {
  exec.test.abort('READ_PATH는 /로 시작해야 합니다.');
}
if (!Number.isInteger(RATE) || RATE <= 0) {
  exec.test.abort('RATE는 1 이상의 정수여야 합니다.');
}

export const options = {
  // VU별 테스트 계정의 access/refresh 쿠키를 반복 요청 사이에도 유지합니다.
  noCookiesReset: true,
  setupTimeout: '5m',
  scenarios: {
    read_observer: {
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
    // 서버가 느려져 예약된 요청 자체를 보내지 못한 경우도 리허설 실패로 판정합니다.
    dropped_iterations: ['count==0'],
    'checks{endpoint:cost_free_read}': ['rate==1'],
    'http_req_failed{endpoint:cost_free_read}': [`rate<=${MAX_FAILURE_RATE}`],
    'http_req_duration{endpoint:cost_free_read}': [`p(99)<${P99_MS}`],
    auth_failures: ['count==0'],
  },
  summaryTrendStats: ['avg', 'min', 'med', 'p(95)', 'p(99)', 'max'],
};

const observationFailures = new Counter('observation_failures');
const authFailures = new Counter('auth_failures');

function emailOf(vuId) {
  return `${TEST_EMAIL_PREFIX}${String(vuId).padStart(2, '0')}@${TEST_EMAIL_DOMAIN}`;
}

function authRequest(name, method, path, body, jar) {
  const params = {
    headers: JSON_HEADERS,
    timeout: HTTP_TIMEOUT,
    tags: { endpoint: 'auth', name },
  };
  if (jar) params.jar = jar;
  return http.request(method, `${BASE_URL}${path}`, body ? JSON.stringify(body) : null, params);
}

function login(email, jar) {
  return authRequest('auth_login', 'POST', '/api/v1/auth/login', {
    email,
    password: TEST_PASSWORD,
  }, jar);
}

// 테스트 계정 모드에서는 k6가 사용할 계정을 준비하고 로그인이 가능한지 먼저 확인합니다.
// 이미 같은 계정이 있으면 회원가입 실패는 무시하고 로그인 결과로 최종 판정합니다.
export function setup() {
  if (!TEST_PASSWORD) return { accountMode: false };

  for (let i = 1; i <= MAX_VUS; i += 1) {
    const email = emailOf(i);
    const jar = new http.CookieJar();
    authRequest('auth_signup', 'POST', '/api/v1/auth/signup', {
      email,
      password: TEST_PASSWORD,
    }, jar);
    const response = login(email, jar);
    if (response.status !== 200) {
      exec.test.abort(`테스트 계정 로그인 실패: ${email} status=${response.status}`);
    }
    // 회원가입·로그인이 Nginx rate limit을 순간적으로 넘지 않도록 준비 요청을 분산합니다.
    sleep(0.1);
  }

  console.log(`읽기 관찰용 테스트 계정 ${MAX_VUS}개 준비 완료`);
  return { accountMode: true };
}

function requestHeaders(requestId) {
  const headers = {
    Accept: 'application/json',
    'X-Request-ID': requestId,
  };
  if (__ENV.AUTH_TOKEN) {
    headers.Authorization = __ENV.AUTH_TOKEN.startsWith('Bearer ')
      ? __ENV.AUTH_TOKEN
      : `Bearer ${__ENV.AUTH_TOKEN}`;
  }
  if (__ENV.COOKIE) {
    headers.Cookie = __ENV.COOKIE;
  }
  return headers;
}

let loggedIn = false;
let lastTokenRefreshAt = 0;

function ensureVuLogin() {
  if (loggedIn) return true;
  const response = login(emailOf(exec.vu.idInTest));
  if (response.status !== 200) {
    authFailures.add(1, { operation: 'login', status: String(response.status) });
    return false;
  }
  loggedIn = true;
  lastTokenRefreshAt = Date.now();
  return true;
}

function refreshVuTokenIfNeeded() {
  if (Date.now() - lastTokenRefreshAt < TOKEN_REFRESH_INTERVAL_MS) return true;
  const response = authRequest('auth_refresh', 'POST', '/api/v1/auth/refresh');
  if (response.status < 200 || response.status >= 300) {
    authFailures.add(1, { operation: 'refresh', status: String(response.status) });
    loggedIn = false;
    return ensureVuLogin();
  }
  lastTokenRefreshAt = Date.now();
  return true;
}

export default function (data) {
  if (data.accountMode && (!ensureVuLogin() || !refreshVuTokenIfNeeded())) {
    return;
  }

  const requestId = `mig-${RUN_ID}-${exec.vu.idInTest}-${exec.scenario.iterationInTest}-${Date.now()}`;
  const response = http.get(`${BASE_URL}${READ_PATH}`, {
    headers: data.accountMode ? { Accept: 'application/json', 'X-Request-ID': requestId } : requestHeaders(requestId),
    timeout: HTTP_TIMEOUT,
    redirects: 0,
    tags: { endpoint: 'cost_free_read', name: 'cost_free_read' },
  });

  const passed = check(
    response,
    {
      [`status is ${EXPECTED_STATUS}`]: (res) => res.status === EXPECTED_STATUS,
      'expected response body is present': (res) =>
        EXPECTED_BODY_TEXT === '' || String(res.body || '').includes(EXPECTED_BODY_TEXT),
    },
    { endpoint: 'cost_free_read' },
  );

  if (!passed) {
    observationFailures.add(1, { endpoint: 'cost_free_read', status: String(response.status) });
    console.error(JSON.stringify({
      at: new Date().toISOString(),
      request_id: requestId,
      status: response.status,
      error: response.error || '',
      error_code: response.error_code || 0,
    }));
  }
}
