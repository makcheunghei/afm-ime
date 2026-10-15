#!/usr/bin/env python3
"""Read public certificate subjects for valid signing identities; never export private keys."""
import hashlib
import re
import ssl
import subprocess
import sys

wanted = set(re.findall(r'^\s*\d+\)\s+([A-Fa-f0-9]{40})\s+"', sys.stdin.read(), re.M))
if not wanted:
    raise SystemExit(0)
certificates = subprocess.run(
    ["security", "find-certificate", "-a", "-p"], check=True, capture_output=True, text=True
).stdout
for pem in re.findall(r"-----BEGIN CERTIFICATE-----.*?-----END CERTIFICATE-----", certificates, re.S):
    digest = hashlib.sha1(ssl.PEM_cert_to_DER_cert(pem)).hexdigest().upper()
    if digest not in wanted:
        continue
    subject = subprocess.run(
        ["/usr/bin/openssl", "x509", "-noout", "-subject", "-nameopt", "RFC2253"],
        input=pem, text=True, capture_output=True, check=True
    ).stdout
    # Apple Development's name suffix can identify the developer rather than the Team.
    # The certificate's organizational unit is the Team used by codesign.
    team = re.search(r"(?:^|,)OU=([A-Z0-9]{10})(?:,|$)", subject)
    if team:
        print(digest, team.group(1))
