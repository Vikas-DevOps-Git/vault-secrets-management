#!/usr/bin/env python3
"""
vault_setup.py — Automated Vault initial configuration
Idempotent setup script for: auth methods, secret engines,
policies, and roles. Safe to re-run — all operations use
create-or-update semantics.

Usage:
    # Dev setup with token auth
    python vault_setup.py --vault-addr http://localhost:8200 --vault-token root

    # Dry run — show what would be configured
    python vault_setup.py --vault-addr http://localhost:8200 --dry-run
"""
import argparse
import json
import logging
import sys
from pathlib import Path

log = logging.getLogger(__name__)
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s [vault_setup] %(message)s"
)


class VaultSetup:
    """Idempotent Vault configuration manager."""

    def __init__(self, client, dry_run: bool = False):
        self.client = client
        self.dry_run = dry_run
        self.changes = []
        self.errors = []

    def _apply(self, description: str, func, *args, **kwargs):
        """Execute a Vault write operation, tracking changes."""
        log.info(f"{'[DRY RUN] ' if self.dry_run else ''}Applying: {description}")
        if self.dry_run:
            self.changes.append({"action": description, "status": "dry_run"})
            return True
        try:
            func(*args, **kwargs)
            self.changes.append({"action": description, "status": "success"})
            return True
        except Exception as e:
            log.error(f"Failed: {description} — {e}")
            self.errors.append({"action": description, "error": str(e)})
            return False

    def enable_auth(self, path: str, auth_type: str):
        try:
            existing = self.client.sys.list_auth_methods()
            if f"{path}/" not in existing:
                self._apply(
                    f"Enable auth method: {auth_type} at {path}",
                    self.client.sys.enable_auth_method,
                    method_type=auth_type,
                    path=path,
                )
            else:
                log.info(f"Auth method {path} already enabled — skipping")
        except Exception as e:
            log.error(f"enable_auth error: {e}")

    def enable_secrets_engine(self, path: str, engine_type: str):
        try:
            existing = self.client.sys.list_mounted_secrets_engines()
            if f"{path}/" not in existing:
                self._apply(
                    f"Enable secrets engine: {engine_type} at {path}",
                    self.client.sys.enable_secrets_engine,
                    backend_type=engine_type,
                    path=path,
                )
            else:
                log.info(f"Secrets engine {path} already enabled — skipping")
        except Exception as e:
            log.error(f"enable_secrets_engine error: {e}")

    def write_policy(self, name: str, policy_hcl: str):
        self._apply(
            f"Write policy: {name}",
            self.client.sys.create_or_update_policy,
            name=name,
            policy=policy_hcl,
        )

    def write_policies_from_dir(self, policy_dir: str):
        policy_path = Path(policy_dir)
        if not policy_path.exists():
            log.warning(f"Policy dir not found: {policy_dir}")
            return
        for hcl_file in sorted(policy_path.glob("*.hcl")):
            policy_name = hcl_file.stem
            policy_content = hcl_file.read_text()
            self.write_policy(policy_name, policy_content)

    def configure_k8s_auth(self, k8s_host: str, ca_cert: str = ""):
        config = {"kubernetes_host": k8s_host}
        if ca_cert:
            config["kubernetes_ca_cert"] = ca_cert

        self._apply(
            f"Configure Kubernetes auth: {k8s_host}",
            self.client.auth.kubernetes.configure,
            **config,
        )

    def create_k8s_role(self, role_name: str, service_accounts: list,
                        namespaces: list, policies: list,
                        ttl: int = 3600, max_ttl: int = 14400):
        self._apply(
            f"Create K8s auth role: {role_name}",
            self.client.auth.kubernetes.create_role,
            name=role_name,
            bound_service_account_names=service_accounts,
            bound_service_account_namespaces=namespaces,
            policies=policies,
            ttl=ttl,
            max_ttl=max_ttl,
        )

    def create_kv_secret(self, path: str, data: dict, mount_point: str = "secret"):
        self._apply(
            f"Write KV secret: {path}",
            self.client.secrets.kv.v2.create_or_update_secret,
            path=path,
            secret=data,
            mount_point=mount_point,
        )

    def run_full_setup(self, k8s_host: str, policy_dir: str):
        """Run complete Vault setup sequence."""
        log.info("Starting full Vault setup...")

        # 1. Enable auth methods
        self.enable_auth("kubernetes", "kubernetes")

        # 2. Enable secrets engines
        self.enable_secrets_engine("secret", "kv")
        self.enable_secrets_engine("database", "database")
        self.enable_secrets_engine("aws", "aws")
        self.enable_secrets_engine("pki", "pki")
        self.enable_secrets_engine("pki_int", "pki")

        # 3. Configure K8s auth
        self.configure_k8s_auth(k8s_host)

        # 4. Write policies from .hcl files
        self.write_policies_from_dir(policy_dir)

        # 5. Create K8s auth roles
        self.create_k8s_role(
            "payment-api",
            ["payment-api-sa"], ["finance"],
            ["payment-api-policy", "common-policy"],
        )
        self.create_k8s_role(
            "notification-service",
            ["notification-service-sa"], ["finance"],
            ["notification-policy", "common-policy"],
        )
        self.create_k8s_role(
            "vault-rotation",
            ["vault-rotation-sa"], ["vault-system"],
            ["rotation-policy"],
            ttl=1800, max_ttl=3600,
        )

        log.info(
            f"Setup complete — "
            f"changes={len(self.changes)}, "
            f"errors={len(self.errors)}"
        )

        return {
            "changes": self.changes,
            "errors": self.errors,
            "status": "success" if not self.errors else "partial",
        }


def main():
    parser = argparse.ArgumentParser(description="Vault Initial Setup")
    parser.add_argument("--vault-addr",
                        default="http://localhost:8200")
    parser.add_argument("--vault-token",
                        default="root")
    parser.add_argument("--k8s-host",
                        default="https://kubernetes.default.svc")
    parser.add_argument("--policy-dir",
                        default="kubernetes-auth/policies")
    parser.add_argument("--dry-run",
                        action="store_true")
    parser.add_argument("--output",
                        default="text", choices=["text", "json"])
    args = parser.parse_args()

    try:
        import hvac
        client = hvac.Client(url=args.vault_addr, token=args.vault_token)
        if not client.is_authenticated():
            log.error("Vault authentication failed")
            sys.exit(1)
    except ImportError:
        log.error("hvac not installed — pip install hvac")
        sys.exit(1)
    except Exception as e:
        log.error(f"Vault connection failed: {e}")
        sys.exit(1)

    setup = VaultSetup(client, dry_run=args.dry_run)
    report = setup.run_full_setup(args.k8s_host, args.policy_dir)

    if args.output == "json":
        print(json.dumps(report, indent=2))
    else:
        print(f"\nVault Setup Report")
        print(f"Changes applied : {len(report['changes'])}")
        print(f"Errors          : {len(report['errors'])}")
        print(f"Status          : {report['status'].upper()}")
        if report["errors"]:
            for e in report["errors"]:
                print(f"  ERROR: {e['action']} — {e['error']}")

    sys.exit(0 if report["status"] != "failed" else 1)


if __name__ == "__main__":
    main()
