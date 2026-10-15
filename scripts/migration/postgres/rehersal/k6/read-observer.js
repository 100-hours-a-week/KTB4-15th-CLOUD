// User-facing availability observer. The default GET is cost-free and passes through
// Nginx and Spring. It does not query the FastAPI PostgreSQL database directly:
// the current FastAPI OpenAPI exposes only GET /health and Nginx has no FastAPI route.
// Use READ_PATH/EXPECTED_BODY_TEXT for a confirmed read scenario when one is available.

import http from 'k6/http';
import exec from 'k6/execution';
import { check } from 'k6';
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

if (!READ_PATH.startsWith('/')) {
  exec.test.abort('READ_PATH는 /로 시작해야 합니다.');
}
if (!Number.isInteger(RATE) || RATE <= 0) {
  exec.test.abort('RATE는 1 이상의 정수여야 합니다.');
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
    'checks{endpoint:cost_free_read}': ['rate==1'],
    'http_req_failed{endpoint:cost_free_read}': [`rate<=${MAX_FAILURE_RATE}`],
    'http_req_duration{endpoint:cost_free_read}': [`p(99)<${P99_MS}`],
  },
  summaryTrendStats: ['avg', 'min', 'med', 'p(95)', 'p(99)', 'max'],
};

const observationFailures = new Counter('observation_failures');

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

export default function () {
  const requestId = `mig-${RUN_ID}-${exec.vu.idInTest}-${exec.scenario.iterationInTest}-${Date.now()}`;
  const response = http.get(`${BASE_URL}${READ_PATH}`, {
    headers: requestHeaders(requestId),
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
