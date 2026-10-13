from unittest.mock import MagicMock, patch

from botocore.exceptions import ClientError


def _login(client, access_key="minio-user", secret_key="minio-secret"):
    with patch("app.boto3.client") as mock_boto:
        mock_minio = MagicMock()
        mock_boto.return_value = mock_minio
        return client.post(
            "/login",
            data={"access_key": access_key, "secret_key": secret_key},
            follow_redirects=False,
        )


def test_login_page_renders(app_client):
    client, _app = app_client
    response = client.get("/login")
    assert response.status_code == 200
    assert b"S3 Browser" in response.data
    assert b"Sign in" in response.data


def test_login_rejects_empty_credentials(app_client):
    client, _app = app_client
    response = client.post("/login", data={"access_key": "", "secret_key": ""})
    assert response.status_code == 400


def test_login_success_redirects_to_index(app_client):
    client, _app = app_client
    response = _login(client)
    assert response.status_code == 302
    assert response.location.endswith("/")


def test_login_failure_on_minio_error(app_client):
    client, _app = app_client
    with patch("app.boto3.client") as mock_boto:
        mock_minio = MagicMock()
        mock_minio.list_objects_v2.side_effect = ClientError(
            {"Error": {"Code": "AccessDenied", "Message": "denied"}},
            "ListObjectsV2",
        )
        mock_boto.return_value = mock_minio
        response = client.post(
            "/login",
            data={"access_key": "bad", "secret_key": "bad"},
        )
    assert response.status_code == 401


def test_index_requires_login(app_client):
    client, _app = app_client
    response = client.get("/")
    assert response.status_code == 302
    assert "/login" in response.location


def test_index_lists_approved_buckets(app_client):
    client, _app = app_client
    _login(client)
    response = client.get("/")
    assert response.status_code == 200
    assert b"approved-one" in response.data
    assert b"approved-two" in response.data


def test_browse_rejects_unapproved_bucket(app_client):
    client, _app = app_client
    _login(client)
    response = client.get("/bucket/not-in-list")
    assert response.status_code == 404


def test_browse_lists_folders_and_objects(app_client):
    client, _app = app_client
    _login(client)

    mock_aws = MagicMock()
    mock_aws.list_objects_v2.return_value = {
        "CommonPrefixes": [{"Prefix": "reports/"}],
        "Contents": [
            {"Key": "reports/", "Size": 0},
            {"Key": "reports/file.txt", "Size": 12, "LastModified": "2024-01-01"},
        ],
        "IsTruncated": False,
    }

    with patch("app.aws_client", return_value=mock_aws):
        response = client.get("/bucket/approved-one?prefix=reports/")

    assert response.status_code == 200
    assert b"file.txt" in response.data
    mock_aws.list_objects_v2.assert_called_once_with(
        Bucket="approved-one",
        Prefix="reports/",
        Delimiter="/",
        MaxKeys=1000,
    )


def test_browse_returns_502_on_aws_error(app_client):
    client, _app = app_client
    _login(client)

    mock_aws = MagicMock()
    mock_aws.list_objects_v2.side_effect = ClientError(
        {"Error": {"Code": "AccessDenied", "Message": "denied"}},
        "ListObjectsV2",
    )

    with patch("app.aws_client", return_value=mock_aws):
        response = client.get("/bucket/approved-one")

    assert response.status_code == 502
    assert b"Unable to access S3" in response.data


def test_browse_rejects_path_traversal(app_client):
    client, _app = app_client
    _login(client)
    response = client.get("/bucket/approved-one?prefix=..%2Fsecret")
    assert response.status_code == 400


def test_download_streams_object(app_client):
    client, _app = app_client
    _login(client)

    body = MagicMock()
    body.iter_chunks.return_value = [b"hello-world"]
    mock_aws = MagicMock()
    mock_aws.get_object.return_value = {"Body": body}

    with patch("app.aws_client", return_value=mock_aws):
        response = client.get("/download/approved-one?key=reports/file.txt")

    assert response.status_code == 200
    assert response.data == b"hello-world"
    mock_aws.get_object.assert_called_once_with(
        Bucket="approved-one",
        Key="reports/file.txt",
    )


def test_download_rejects_unapproved_bucket(app_client):
    client, _app = app_client
    _login(client)
    response = client.get("/download/other-bucket?key=a.txt")
    assert response.status_code == 404
