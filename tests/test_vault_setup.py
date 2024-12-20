"""
test_vault_setup.py — Unit tests for vault_setup.py
Tests idempotency, error handling, and policy loading.
No Vault server required — uses mocks.
"""
import pytest
from unittest.mock import MagicMock, patch, call
from pathlib import Path
import tempfile
import os
import sys

sys.path.insert(0, str(Path(__file__).parent.parent / "scripts"))
from vault_setup import VaultSetup


def make_mock_client(auth_methods=None, secrets_engines=None):
    client = MagicMock()
    client.is_authenticated.return_value = True
    client.sys.list_auth_methods.return_value = auth_methods or {}
    client.sys.list_mounted_secrets_engines.return_value = secrets_engines or {}
    return client


class TestVaultSetupAuth:
    def test_enable_auth_when_not_present(self):
        client = make_mock_client(auth_methods={})
        setup = VaultSetup(client)
        setup.enable_auth("kubernetes", "kubernetes")
        client.sys.enable_auth_method.assert_called_once()

    def test_skip_auth_when_already_enabled(self):
        client = make_mock_client(auth_methods={"kubernetes/": {}})
        setup = VaultSetup(client)
        setup.enable_auth("kubernetes", "kubernetes")
        client.sys.enable_auth_method.assert_not_called()

    def test_dry_run_does_not_call_vault(self):
        client = make_mock_client(auth_methods={})
        setup = VaultSetup(client, dry_run=True)
        setup.enable_auth("kubernetes", "kubernetes")
        client.sys.enable_auth_method.assert_not_called()
        assert setup.changes[0]["status"] == "dry_run"


class TestVaultSetupSecrets:
    def test_enable_secrets_engine(self):
        client = make_mock_client(secrets_engines={})
        setup = VaultSetup(client)
        setup.enable_secrets_engine("database", "database")
        client.sys.enable_secrets_engine.assert_called_once()

    def test_skip_secrets_engine_when_mounted(self):
        client = make_mock_client(secrets_engines={"database/": {}})
        setup = VaultSetup(client)
        setup.enable_secrets_engine("database", "database")
        client.sys.enable_secrets_engine.assert_not_called()


class TestVaultSetupPolicies:
    def test_write_policy(self):
        client = make_mock_client()
        setup = VaultSetup(client)
        setup.write_policy("test-policy", 'path "secret/*" { capabilities = ["read"] }')
        client.sys.create_or_update_policy.assert_called_once_with(
            name="test-policy",
            policy='path "secret/*" { capabilities = ["read"] }',
        )

    def test_write_policies_from_dir(self):
        client = make_mock_client()
        setup = VaultSetup(client)
        with tempfile.TemporaryDirectory() as tmpdir:
            for name in ["policy-a.hcl", "policy-b.hcl"]:
                Path(tmpdir, name).write_text(
                    f'path "secret/*" {{ capabilities = ["read"] }}'
                )
            setup.write_policies_from_dir(tmpdir)
        assert client.sys.create_or_update_policy.call_count == 2

    def test_missing_policy_dir_does_not_crash(self):
        client = make_mock_client()
        setup = VaultSetup(client)
        setup.write_policies_from_dir("/nonexistent/path")
        client.sys.create_or_update_policy.assert_not_called()


class TestVaultSetupRoles:
    def test_create_k8s_role(self):
        client = make_mock_client()
        setup = VaultSetup(client)
        setup.create_k8s_role(
            "payment-api",
            ["payment-api-sa"], ["finance"],
            ["payment-api-policy"],
        )
        client.auth.kubernetes.create_role.assert_called_once()

    def test_k8s_role_dry_run(self):
        client = make_mock_client()
        setup = VaultSetup(client, dry_run=True)
        setup.create_k8s_role(
            "payment-api",
            ["payment-api-sa"], ["finance"],
            ["payment-api-policy"],
        )
        client.auth.kubernetes.create_role.assert_not_called()


class TestVaultSetupErrorHandling:
    def test_error_tracked_in_errors_list(self):
        client = make_mock_client()
        client.sys.create_or_update_policy.side_effect = Exception("Connection error")
        setup = VaultSetup(client)
        setup.write_policy("failing-policy", "invalid hcl")
        assert len(setup.errors) == 1
        assert "Connection error" in setup.errors[0]["error"]

    def test_partial_status_on_errors(self):
        client = make_mock_client(auth_methods={}, secrets_engines={})
        client.sys.enable_auth_method.side_effect = Exception("Permission denied")
        setup = VaultSetup(client)
        setup.enable_auth("kubernetes", "kubernetes")
        assert any(e["status"] == "failed" or
                   "error" in e for e in setup.errors)
