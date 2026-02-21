import os
from vpn_manager import VPNManager

manager = VPNManager(os.path.dirname(os.path.abspath(__file__)))
session, url = manager.login_xui()

print(f"Logged in successfully. URL: {url}")

res = session.get(f"{url}/panel/api/inbounds/list")
print(f"Status: {res.status_code}")
print(f"Headers: {res.headers.get('Content-Type')}")

try:
    data = res.json()
    print("Inbounds JSON:")
    for inb in data.get('obj', []):
        print(f" - ID: {inb.get('id')}, Port: {inb.get('port')}, Remark: {inb.get('remark')}")
except Exception as e:
    print(f"Failed to decode JSON: {e}")
    print("Raw text snippet:", res.text[:500])
