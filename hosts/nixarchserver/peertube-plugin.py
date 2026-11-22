import json
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

credentials = dict(
    line.split("=", 1)
    for line in Path("/run/nixarchserver-peertube/credentials").read_text().splitlines()
)
base = "http://10.1.0.2:9001/api/v1"
headers = {"Host": "videos.valhallishe.net", "X-Forwarded-Proto": "https"}


def request(path, method="GET", body=None, form=False):
    request_headers = headers.copy()
    if body is not None:
        body = (urllib.parse.urlencode(body) if form else json.dumps(body)).encode()
        request_headers["Content-Type"] = (
            "application/x-www-form-urlencoded" if form else "application/json"
        )
    with urllib.request.urlopen(
        urllib.request.Request(base + path, data=body, headers=request_headers, method=method),
        timeout=300,
    ) as response:
        data = response.read()
        return json.loads(data) if data else None


client = request("/oauth-clients/local")
token = request(
    "/users/token", "POST",
    {"client_id": client["client_id"], "client_secret": client["client_secret"],
     "grant_type": "password", "username": "root", "password": credentials["PEERTUBE_ADMIN_PASSWORD"][:40]},
    form=True,
)
headers["Authorization"] = "Bearer " + token["access_token"]
plugin = "peertube-plugin-auth-openid-connect"
try:
    request("/plugins/" + plugin)
except urllib.error.HTTPError as error:
    if error.code != 404:
        raise
    request("/plugins/install", "POST", {"npmName": plugin})

request("/plugins/" + plugin + "/settings", "PUT", {"settings": {
    "auth-display-name": "Valhallishe SSO",
    "discover-url": "https://sso.valhallishe.net/application/o/peertube/.well-known/openid-configuration",
    "client-id": "peertube",
    "client-secret": credentials["OIDC_SECRET"],
    "scope": "openid profile email",
    "username-property": "preferred_username",
    "mail-property": "email",
    "external-id-property": "sub",
}})
