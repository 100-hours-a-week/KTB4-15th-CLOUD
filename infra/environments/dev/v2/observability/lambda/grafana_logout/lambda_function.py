"""Grafana 로그아웃: ALB 인증 쿠키와 Grafana 세션 쿠키를 지우고 Cognito 로그아웃으로 보낸다.

ALB 규칙이 grafana 도메인의 /logout 요청을 이 함수로 보낸다 (인증 액션 없음).
ALB 인증 쿠키는 HttpOnly라 브라우저 스크립트나 Grafana가 지울 수 없어서,
같은 도메인에서 만료된 Set-Cookie 헤더를 내려 지운다.
"""

import os

# ALB는 세션 쿠키가 크면 -0, -1 ... 로 나눠 저장한다 (최대 4개)
COOKIES = [f"AWSELBAuthSessionCookie-{i}" for i in range(4)] + [
    "grafana_session",
    "grafana_session_expiry",
]

EXPIRED = "Path=/; Expires=Thu, 01 Jan 1970 00:00:00 GMT; Max-Age=0; Secure; HttpOnly; SameSite=Lax"


def lambda_handler(event, context):
    return {
        "statusCode": 302,
        "statusDescription": "302 Found",
        "isBase64Encoded": False,
        "multiValueHeaders": {
            "Location": [os.environ["COGNITO_LOGOUT_URL"]],
            "Cache-Control": ["no-store"],
            "Set-Cookie": [f"{name}=; {EXPIRED}" for name in COOKIES],
        },
        "body": "",
    }
