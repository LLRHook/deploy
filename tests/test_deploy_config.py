"""Tests for deploy_config.py"""

import json
import os
import sys
import tempfile
import pytest

# Add scripts dir to path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "scripts"))

from deploy_config import (
    SCHEMA_VERSION,
    TEMPLATE,
    config_path,
    init_config,
    read_config,
    update_config,
    validate_config,
)


@pytest.fixture
def tmp_repo(tmp_path):
    """Create a temporary directory acting as a repo root."""
    return str(tmp_path)


@pytest.fixture
def initialized_repo(tmp_repo):
    """Create a repo with an initialized .deploy.json."""
    init_config(tmp_repo, "nextjs-fullstack")
    return tmp_repo


class TestConfigPath:
    def test_returns_deploy_json_path(self, tmp_repo):
        path = config_path(tmp_repo)
        assert path.name == ".deploy.json"
        assert str(path).startswith(tmp_repo)


class TestInitConfig:
    def test_creates_file(self, tmp_repo):
        init_config(tmp_repo, "nextjs-fullstack")
        assert config_path(tmp_repo).exists()

    def test_sets_architecture(self, tmp_repo):
        cfg = init_config(tmp_repo, "nextjs-fullstack")
        assert cfg["architecture"] == "nextjs-fullstack"

    def test_sets_version(self, tmp_repo):
        cfg = init_config(tmp_repo, "separate-frontend-backend")
        assert cfg["version"] == SCHEMA_VERSION

    def test_sets_created_at(self, tmp_repo):
        cfg = init_config(tmp_repo, "nextjs-fullstack")
        assert cfg["createdAt"] is not None

    def test_last_deployed_is_null(self, tmp_repo):
        cfg = init_config(tmp_repo, "nextjs-fullstack")
        assert cfg["lastDeployed"] is None

    def test_file_is_valid_json(self, tmp_repo):
        init_config(tmp_repo, "nextjs-fullstack")
        with open(config_path(tmp_repo)) as f:
            data = json.load(f)
        assert data["architecture"] == "nextjs-fullstack"

    def test_has_vercel_section(self, tmp_repo):
        cfg = init_config(tmp_repo, "nextjs-fullstack")
        assert "vercel" in cfg
        assert "projectId" in cfg["vercel"]
        assert "envVars" in cfg["vercel"]
        assert isinstance(cfg["vercel"]["envVars"], list)

    def test_has_railway_section(self, tmp_repo):
        cfg = init_config(tmp_repo, "nextjs-fullstack")
        assert "railway" in cfg
        assert "services" in cfg["railway"]
        assert "postgres" in cfg["railway"]["services"]
        assert cfg["railway"]["services"]["postgres"]["connectionVar"] == "DATABASE_URL"

    def test_has_stripe_section(self, tmp_repo):
        cfg = init_config(tmp_repo, "nextjs-fullstack")
        assert cfg["stripe"]["mode"] == "test"
        assert cfg["stripe"]["webhookConfigured"] is False


class TestReadConfig:
    def test_reads_existing_config(self, initialized_repo):
        cfg = read_config(initialized_repo)
        assert cfg["architecture"] == "nextjs-fullstack"

    def test_exits_on_missing_file(self, tmp_repo):
        with pytest.raises(SystemExit):
            read_config(tmp_repo)


class TestUpdateConfig:
    def test_update_simple_key(self, initialized_repo):
        cfg = update_config(initialized_repo, "vercel.projectId", "prj_123")
        assert cfg["vercel"]["projectId"] == "prj_123"

    def test_update_nested_key(self, initialized_repo):
        cfg = update_config(
            initialized_repo, "railway.services.postgres.serviceId", "svc_abc"
        )
        assert cfg["railway"]["services"]["postgres"]["serviceId"] == "svc_abc"

    def test_update_sets_last_deployed(self, initialized_repo):
        cfg = update_config(initialized_repo, "vercel.projectId", "prj_123")
        assert cfg["lastDeployed"] is not None

    def test_update_persists_to_disk(self, initialized_repo):
        update_config(initialized_repo, "vercel.projectId", "prj_456")
        cfg = read_config(initialized_repo)
        assert cfg["vercel"]["projectId"] == "prj_456"

    def test_update_boolean_value(self, initialized_repo):
        cfg = update_config(initialized_repo, "stripe.webhookConfigured", "true")
        assert cfg["stripe"]["webhookConfigured"] is True

    def test_update_array_value(self, initialized_repo):
        cfg = update_config(
            initialized_repo,
            "vercel.envVars",
            '["DATABASE_URL", "STRIPE_SECRET_KEY"]',
        )
        assert cfg["vercel"]["envVars"] == ["DATABASE_URL", "STRIPE_SECRET_KEY"]

    def test_update_creates_missing_intermediate_keys(self, initialized_repo):
        cfg = update_config(initialized_repo, "custom.nested.key", "value")
        assert cfg["custom"]["nested"]["key"] == "value"

    def test_update_preserves_other_fields(self, initialized_repo):
        update_config(initialized_repo, "vercel.projectId", "prj_789")
        cfg = read_config(initialized_repo)
        assert cfg["architecture"] == "nextjs-fullstack"
        assert cfg["railway"]["services"]["postgres"]["connectionVar"] == "DATABASE_URL"


class TestValidateConfig:
    def test_fresh_config_fails_validation(self, initialized_repo):
        assert validate_config(initialized_repo) is False

    def test_complete_config_passes(self, initialized_repo):
        update_config(initialized_repo, "vercel.projectId", "prj_123")
        update_config(initialized_repo, "vercel.deploymentUrl", "https://app.vercel.app")
        update_config(initialized_repo, "railway.projectId", "rw_proj_123")
        update_config(initialized_repo, "railway.environmentId", "rw_env_123")
        update_config(
            initialized_repo, "railway.services.postgres.serviceId", "svc_pg"
        )
        assert validate_config(initialized_repo) is True

    def test_missing_vercel_project_id_fails(self, initialized_repo):
        update_config(initialized_repo, "vercel.deploymentUrl", "https://app.vercel.app")
        update_config(initialized_repo, "railway.projectId", "rw_proj_123")
        update_config(initialized_repo, "railway.environmentId", "rw_env_123")
        update_config(
            initialized_repo, "railway.services.postgres.serviceId", "svc_pg"
        )
        assert validate_config(initialized_repo) is False

    def test_missing_deployment_url_fails(self, initialized_repo):
        update_config(initialized_repo, "vercel.projectId", "prj_123")
        update_config(initialized_repo, "railway.projectId", "rw_proj_123")
        update_config(initialized_repo, "railway.environmentId", "rw_env_123")
        update_config(
            initialized_repo, "railway.services.postgres.serviceId", "svc_pg"
        )
        assert validate_config(initialized_repo) is False

    def test_missing_postgres_service_fails(self, initialized_repo):
        update_config(initialized_repo, "vercel.projectId", "prj_123")
        update_config(initialized_repo, "vercel.deploymentUrl", "https://app.vercel.app")
        update_config(initialized_repo, "railway.projectId", "rw_proj_123")
        update_config(initialized_repo, "railway.environmentId", "rw_env_123")
        assert validate_config(initialized_repo) is False
