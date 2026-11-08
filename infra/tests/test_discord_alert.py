import importlib.util
import json
import sys
import types
import unittest
from pathlib import Path
from unittest.mock import patch


LAMBDA_PATH = (
    Path(__file__).parents[1]
    / "environments/prod/v1/monitoring/lambda/discord_alert/lambda_function.py"
)


class FakeSsmClient:
    def get_parameter(self, Name, WithDecryption):
        return {"Parameter": {"Value": f"https://discord.invalid/{Name.rsplit('/', 1)[-1]}"}}


class FakeLogsClient:
    pass


def load_lambda_module():
    boto3 = types.ModuleType("boto3")
    boto3.client = lambda service: FakeSsmClient() if service == "ssm" else FakeLogsClient()

    spec = importlib.util.spec_from_file_location("discord_alert_lambda", LAMBDA_PATH)
    module = importlib.util.module_from_spec(spec)
    with patch.dict(sys.modules, {"boto3": boto3}):
        spec.loader.exec_module(module)
    return module


class ArgoCdAlertTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.module = load_lambda_module()

    def event(self, **detail):
        defaults = {
            "environment": "dev",
            "application": "dev-web-bff",
            "project": "lookddak-dev",
            "namespace": "lookddak-web",
            "workload": "web-bff",
            "syncStatus": "OutOfSync",
            "healthStatus": "Degraded",
            "phase": "Failed",
            "message": "Deployment exceeded its progress deadline",
            "revision": "0123456789abcdef",
            "digest": "sha256:" + "a" * 64,
            "argocdUrl": "https://argocd.dev.lookddak.com/applications/argocd/dev-web-bff",
            "gitopsUrl": "https://github.com/100-hours-a-week/KTB4-15th-GITOPS/commit/0123456",
            "sourceCommitUrl": "https://github.com/100-hours-a-week/KTB4-15th-FE/commit/abcdef0",
            "sourceActionsUrl": "https://github.com/100-hours-a-week/KTB4-15th-FE/actions/runs/1",
        }
        defaults.update(detail)
        return {"source": "custom.argocd", "detail": defaults}

    def test_sync_failure_uses_critical_webhook_and_trace_links(self):
        alert = self.module.parse_event(self.event())

        self.assertEqual(alert["state"], "ALARM")
        self.assertEqual(alert["webhook"], self.module.CRITICAL_WEBHOOK_URL)
        self.assertEqual(alert["title"], "[DEV][배포 실패] dev-web-bff")
        self.assertIn("원본 Actions", alert["description"])
        self.assertIn(("워크로드", "web-bff"), alert["fields"])
        self.assertIn(("Image Digest", "sha256:" + "a" * 64), alert["fields"])

    def test_health_degraded_without_failed_phase_is_alerted(self):
        alert = self.module.parse_event(
            self.event(phase="Succeeded", syncStatus="Synced", healthStatus="Degraded")
        )

        self.assertIsNotNone(alert)
        self.assertEqual(alert["state"], "ALARM")

    def test_sync_unknown_is_alerted(self):
        alert = self.module.parse_event(
            self.event(phase="", syncStatus="Unknown", healthStatus="Healthy")
        )

        self.assertIsNotNone(alert)

    def test_success_event_is_ignored(self):
        alert = self.module.parse_event(
            self.event(phase="Succeeded", syncStatus="Synced", healthStatus="Healthy")
        )

        self.assertIsNone(alert)

    def test_malformed_argocd_record_is_reported_for_sqs_retry(self):
        event = {
            "Records": [
                {"messageId": "bad-message", "body": json.dumps({"source": "custom.argocd"})}
            ]
        }

        result = self.module.lambda_handler(event, None)

        self.assertEqual(result, {"batchItemFailures": [{"itemIdentifier": "bad-message"}]})


if __name__ == "__main__":
    unittest.main()
