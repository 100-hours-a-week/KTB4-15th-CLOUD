// 사용자 관점에서 Dev 서비스의 읽기 요청이 전환 중에도 계속 성공하는지 관찰한다.
// TEST_PASSWORD를 주면 VU별 테스트 계정을 만들고 45초마다 인증을 갱신하여
// 짧은 access token 만료 때문에 장시간 리허설이 401로 실패하는 일을 방지한다.

import http from 'k6/http';
import exec from 'k6/execution';
import { check } from 'k6';
import { Counter } from 'k6/metrics';

const BASE_URL = (__ENV.BASE_URL || 'https://dev.lookddak.com').replace(/\/$/, '');
const READ_PATH = __ENV.READ_PATH || '/api/v1/chat-rooms';
const RATE = Number.parseInt(__ENV.RATE || '20', 10);
const DURATION = __ENV.DURATION || '5m';
const HTTP_TIMEOUT = __ENV.HTTP_TIMEOUT || '10s';
const EXPECTED_STATUS = Number.parseInt(__ENV.EXPECTED_STATUS || '200', 10);
const EXPECTED_BODY_TEXT = __ENV.EXPECTED_BODY_TEXT || '';
const RUN_ID = __ENV.RUN_ID || `read-${Date.now()}`;
const MAX_FAILURE_RATE = Number.parseFloat(__ENV.MAX_FAILURE_RATE || '0');
const P99_MS = Number.parseInt(__ENV.P99_MS || '5000', 10);
const PREALLOCATED_VUS = Number.parseInt(__ENV.PREALLOCATED_VUS || String(Math.max(20, RATE)), 10);
const MAX_VUS = Number.parseInt(__ENV.MAX_VUS || String(Math.max(40, RATE * 2)), 10);
const TEST_PASSWORD = __ENV.TEST_PASSWORD || '';
const TOKEN_REFRESH_INTERVAL_MS = Number.parseInt(__ENV.TOKEN_REFRESH_INTERVAL_MS || '45000', 10);
const TEST_EMAIL_PREFIX = (__ENV.TEST_EMAIL_PREFIX || `pg-rehearsal-${RUN_ID}-`)
  .replace(/[^A-Za-z0-9._-]/g, '-')
  .slice(0, 80);

if (!READ_PATH.startsWith('/')) {
  exec.test.abort('READ_PATH는 /로 시작해야 합니다.');
}
if (!Number.isInteger(RATE) || RATE <= 0) {
  exec.test.abort('RATE는 1 이상의 정수여야 합니다.');
}
if (!Number.isInteger(PREALLOCATED_VUS) || !Number.isInteger(MAX_VUS) || PREALLOCATED_VUS <= 0 || MAX_VUS < PREALLOCATED_VUS) {
  exec.test.abort('PREALLOCATED_VUS와 MAX_VUS 설정을 확인하세요.');
}

export const options = {
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
    dropped_iterations: ['count==0'],
    'checks{endpoint:cost_free_read}': ['rate==1'],
    'http_req_failed{endpoint:cost_free_read}': [`rate<=${MAX_FAILURE_RATE}`],
    'http_req_duration{endpoint:cost_free_read}': [`p(99)<${P99_MS}`],
  },
  summaryTrendStats: ['avg', 'min', 'med', 'p(95)', 'p(99)', 'max'],
};

const observationFailures = new Counter('observation_failures');
let authenticated = false;
let lastAuthenticationAt = 0;
let sessionCookie = '';

function authParams(name, cookie = '') {
  const headers = { Accept: 'application/json', 'Content-Type': 'application/json' };
  if (cookie) headers.Cookie = cookie;
  return {
    headers,
    timeout: HTTP_TIMEOUT,
    redirects: 0,
    tags: { endpoint: 'auth', name },
  };
}

function cookieHeader(response) {
  const parts = [];
  for (const [name, values] of Object.entries(response.cookies || {})) {
    if (values && values.length && values[0].value) parts.push(`${name}=${values[0].value}`);
  }
  return parts.join('; ');
}

export function setup() {
  if (!TEST_PASSWORD) {
    if (!__ENV.AUTH_TOKEN && !__ENV.COOKIE) {
      exec.test.abort('TEST_PASSWORD 또는 AUTH_TOKEN/COOKIE 중 하나가 필요합니다.');
    }
    return { sessions: [] };
  }

  const nonce = Date.now();
  const sessions = [];
  for (let i = 1; i <= MAX_VUS; i += 1) {
    const user = { email: `${TEST_EMAIL_PREFIX}${nonce}-${i}@example.com`, password: TEST_PASSWORD };
    const signup = http.post(`${BASE_URL}/api/v1/auth/signup`, JSON.stringify(user), authParams('auth_signup'));
    if (signup.status !== 201) {
      exec.test.abort(`테스트 계정 생성 실패: index=${i}, status=${signup.status}`);
    }
    const login = http.post(`${BASE_URL}/api/v1/auth/login`, JSON.stringify(user), authParams('auth_login'));
    if (login.status !== 200) {
      exec.test.abort(`테스트 계정 로그인 확인 실패: index=${i}, status=${login.status}`);
    }
    const cookie = cookieHeader(login);
    if (!cookie.includes('accessToken=') || !cookie.includes('refreshToken=')) {
      exec.test.abort(`로그인 쿠키 추출 실패: index=${i}`);
    }
    sessions.push({ user, cookie });
  }
  return { sessions };
}

function login(user) {
  const response = http.post(`${BASE_URL}/api/v1/auth/login`, JSON.stringify(user), authParams('auth_login'));
  const cookie = cookieHeader(response);
  if (response.status !== 200 || !cookie.includes('accessToken=') || !cookie.includes('refreshToken=')) {
    exec.test.abort(`VU 로그인 실패: vu=${exec.vu.idInTest}, status=${response.status}`);
  }
  sessionCookie = cookie;
  authenticated = true;
  lastAuthenticationAt = Date.now();
}

function ensureAuthentication(data) {
  if (!data.sessions.length) return;
  const session = data.sessions[(exec.vu.idInTest - 1) % data.sessions.length];
  if (!authenticated) {
    sessionCookie = session.cookie;
    authenticated = true;
    lastAuthenticationAt = Date.now();
  }
  if (Date.now() - lastAuthenticationAt < TOKEN_REFRESH_INTERVAL_MS) return;

  const refreshed = http.post(`${BASE_URL}/api/v1/auth/refresh`, null, authParams('auth_refresh', sessionCookie));
  const cookie = cookieHeader(refreshed);
  if (refreshed.status === 200 && cookie.includes('accessToken=') && cookie.includes('refreshToken=')) {
    sessionCookie = cookie;
    lastAuthenticationAt = Date.now();
    return;
  }
  login(session.user);
}

function requestHeaders(requestId) {
  const headers = { Accept: 'application/json', 'X-Request-ID': requestId };
  if (__ENV.AUTH_TOKEN) {
    headers.Authorization = __ENV.AUTH_TOKEN.startsWith('Bearer ') ? __ENV.AUTH_TOKEN : `Bearer ${__ENV.AUTH_TOKEN}`;
  }
  if (sessionCookie) headers.Cookie = sessionCookie;
  else if (__ENV.COOKIE) headers.Cookie = __ENV.COOKIE;
  return headers;
}

export default function (data) {
  ensureAuthentication(data);
  const requestId = `mig-${RUN_ID}-${exec.vu.idInTest}-${exec.scenario.iterationInTest}-${Date.now()}`;
  const response = http.get(`${BASE_URL}${READ_PATH}`, {
    headers: requestHeaders(requestId),
    timeout: HTTP_TIMEOUT,
    redirects: 0,
    tags: { endpoint: 'cost_free_read', name: 'cost_free_read' },
  });

  const passed = check(response, {
    [`status is ${EXPECTED_STATUS}`]: (res) => res.status === EXPECTED_STATUS,
    'expected response body is present': (res) => EXPECTED_BODY_TEXT === '' || String(res.body || '').includes(EXPECTED_BODY_TEXT),
  }, { endpoint: 'cost_free_read' });

  if (!passed) {
    observationFailures.add(1, { endpoint: 'cost_free_read', status: String(response.status) });
    console.error(JSON.stringify({
      at: new Date().toISOString(), request_id: requestId, status: response.status,
      error: response.error || '', error_code: response.error_code || 0,
    }));
  }
}
