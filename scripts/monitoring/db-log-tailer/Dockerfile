# RDS 로그 파일 수집기 (tailer.py). 서버에서 docker compose build로 만든다.
FROM python:3.12.7-slim

RUN pip install --no-cache-dir boto3==1.35.0 \
    && mkdir /state && chown 65534:65534 /state

WORKDIR /app
COPY tailer.py /app/tailer.py

# nobody. /state(named volume)는 처음 연결할 때 이미지의 소유자(65534)를 그대로 받는다
USER 65534
ENTRYPOINT ["python", "-u", "/app/tailer.py"]
