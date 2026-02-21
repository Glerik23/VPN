import os
import re
import json
import uuid
import secrets
import base64
import requests
import tarfile
import shutil
import subprocess
from datetime import datetime
from dotenv import set_key, load_dotenv

import urllib.request
import urllib.error

class VPNManager:
    def __init__(self, project_dir):
        self.project_dir = project_dir
        self.env_path = os.path.join(project_dir, '.env')
        load_dotenv(self.env_path)
    
    def get_env(self, key, default=""):
        return os.environ.get(key, default)
    
    def set_env(self, key, value):
        set_key(self.env_path, key, value)
        os.environ[key] = value

    def _generate_x25519_keys(self):
        # The most reliable way for Xray is to use Xray's own generator via Docker.
        # This guarantees 100% compatibility and prevents "reality verification failed" errors.
        try:
            output = subprocess.check_output(
                ["docker", "run", "--rm", "teddysun/xray:latest", "x25519"], 
                timeout=15, stderr=subprocess.DEVNULL
            ).decode('utf-8')
            
            priv_key = ""
            pub_key = ""
            for line in output.split('\n'):
                if "Private" in line:
                    priv_key = line.split(':')[-1].strip()
                elif "Public" in line:
                    pub_key = line.split(':')[-1].strip()
            
            if priv_key and pub_key:
                return priv_key, pub_key
        except Exception:
            pass

        # Fallback to python's cryptography module if available
        try:
            from cryptography.hazmat.primitives.asymmetric import x25519
            from cryptography.hazmat.primitives import serialization
            private_key = x25519.X25519PrivateKey.generate()
            public_key = private_key.public_key()
            
            # Xray format: raw 32 bytes encoded in URL-safe base64 without padding
            priv_bytes = private_key.private_bytes(
                encoding=serialization.Encoding.Raw,
                format=serialization.PrivateFormat.Raw,
                encryption_algorithm=serialization.NoEncryption()
            )
            pub_bytes = public_key.public_bytes(
                encoding=serialization.Encoding.Raw,
                format=serialization.PublicFormat.Raw
            )
            
            priv_b64 = base64.urlsafe_b64encode(priv_bytes).decode('utf-8').rstrip('=')
            pub_b64 = base64.urlsafe_b64encode(pub_bytes).decode('utf-8').rstrip('=')
            return priv_b64, pub_b64
        except ImportError:
            # Final fallback to openssl
            priv_pem = "/tmp/reality_priv.pem"
            pub_pem = "/tmp/reality_pub.pem"
            subprocess.run(["openssl", "genpkey", "-algorithm", "x25519", "-out", priv_pem], check=True, stderr=subprocess.DEVNULL)
            subprocess.run(["openssl", "pkey", "-in", priv_pem, "-pubout", "-out", pub_pem], check=True, stderr=subprocess.DEVNULL)
            
            priv_der = subprocess.check_output(["openssl", "pkey", "-in", priv_pem, "-outform", "DER"])
            pub_der = subprocess.check_output(["openssl", "pkey", "-in", pub_pem, "-pubin", "-outform", "DER"])
            
            priv_b64 = base64.urlsafe_b64encode(priv_der[-32:]).decode('utf-8').rstrip('=')
            pub_b64 = base64.urlsafe_b64encode(pub_der[-32:]).decode('utf-8').rstrip('=')
            
            os.remove(priv_pem)
            os.remove(pub_pem)
            return priv_b64, pub_b64

    def generate_keys(self):
        priv_key, pub_key = self._generate_x25519_keys()
        
        vless_uuid = str(uuid.uuid4())
        short_id = secrets.token_hex(4)
        hysteria_pwd = secrets.token_urlsafe(18)[:24]
        hysteria_obfs = secrets.token_urlsafe(18)[:24]
        
        self.set_env("REALITY_PRIVATE_KEY", priv_key)
        self.set_env("REALITY_PUBLIC_KEY", pub_key)
        self.set_env("REALITY_SHORT_ID", short_id)
        self.set_env("VLESS_UUID", vless_uuid)
        self.set_env("HYSTERIA_PASSWORD", hysteria_pwd)
        self.set_env("HYSTERIA_OBFS_PASSWORD", hysteria_obfs)

    def login_xui(self):
        port = self.get_env("XUI_PORT", "2053")
        username = self.get_env("XUI_USERNAME", "admin")
        password = self.get_env("XUI_PASSWORD", "admin")
        
        url = f"http://localhost:{port}"
        session = requests.Session()
        res = session.post(f"{url}/login", data={"username": username, "password": password})
        
        if not res.json().get('success'):
            # Fallback to admin/admin
            res = session.post(f"{url}/login", data={"username": "admin", "password": "admin"})
            if res.json().get('success'):
                # Update to secure credentials
                session.post(f"{url}/panel/setting/updateUser", data={
                    "oldUsername": "admin", "oldPassword": "admin",
                    "newUsername": username, "newPassword": password
                })
            else:
                raise Exception("Failed to login to 3x-ui")
        
        return session, url

    def setup_inbound(self):
        session, url = self.login_xui()
        
        # Find existing 443 inbound
        res = session.get(f"{url}/panel/api/inbounds/list")
        existing_id = None
        for inb in res.json().get('obj', []):
            if inb.get('port') == 443:
                existing_id = inb.get('id')
                break
                
        if existing_id:
            session.post(f"{url}/panel/api/inbounds/del/{existing_id}")
            
        sni = self.get_env("REALITY_SNI", "www.microsoft.com")
        
        # Create new inbound
        inbound_data = {
            "up": 0, "down": 0, "total": 0,
            "remark": "VLESS-REALITY-AUTO",
            "enable": True,
            "expiryTime": 0,
            "listen": "",
            "port": 443,
            "protocol": "vless",
            "settings": json.dumps({
                "clients": [{"id": self.get_env("VLESS_UUID"), "flow": "xtls-rprx-vision", "email": "client@vpn"}],
                "decryption": "none", "fallbacks": []
            }),
            "streamSettings": json.dumps({
                "network": "tcp", "security": "reality",
                "realitySettings": {
                    "show": False, "dest": f"{sni}:443", "proxyProtocol": 0,
                    "serverNames": [sni],
                    "privateKey": self.get_env("REALITY_PRIVATE_KEY"),
                    "minClient": "", "maxClient": "", "format": "",
                    "shortIds": [self.get_env("REALITY_SHORT_ID")]
                },
                "tcpSettings": {"header": {"type": "none"}}
            }),
            "sniffing": json.dumps({"enabled": True, "destOverride": ["http", "tls"]})
        }
        res = session.post(f"{url}/panel/api/inbounds/add", json=inbound_data)
        if not res.json().get('success'):
            raise Exception(f"Failed to add inbound: {res.text}")
            
        # Warp Outbound Setup
        res = session.get(f"{url}/panel/api/server/getConfigJson")
        config_obj = res.json().get('obj', {})
        if isinstance(config_obj, str):
            config_obj = json.loads(config_obj)
            
        outbounds = config_obj.get('outbounds', [])
        if not any(o.get('tag') == 'warp' for o in outbounds):
            outbounds.append({
                'protocol': 'socks',
                'tag': 'warp',
                'settings': {'servers': [{'address': '127.0.0.1', 'port': 1080}]}
            })
            config_obj['outbounds'] = outbounds
            
            # Routing
            routing = config_obj.setdefault('routing', {})
            rules = routing.setdefault('rules', [])
            if not any(r.get('outboundTag') == 'warp' for r in rules):
                rules.insert(0, {
                    'type': 'field',
                    'outboundTag': 'warp',
                    'domain': [
                        'geosite:openai', 'geosite:netflix', 'geosite:disney',
                        'geosite:primevideo', 'geosite:twitter', 'geosite:instagram',
                        'geosite:meta', 'domain:chatgpt.com', 'domain:antigravity.com'
                    ]
                })
            
            # Since we modify xray template via sqlite directly in the bash script, let's do it similarly just to be safe if getConfigJson doesn't save to template DB
            # but wait, can we update setting via API? Yes: /panel/setting/update
            settings_to_update = {"xrayTemplateConfig": json.dumps(config_obj, indent=2)}
            session.post(f"{url}/panel/setting/update", data=settings_to_update)
            subprocess.run(["docker", "restart", "3x-ui"], check=False)

    def get_client_links(self):
        vless_uuid = self.get_env("VLESS_UUID")
        pub_key = self.get_env("REALITY_PUBLIC_KEY")
        short_id = self.get_env("REALITY_SHORT_ID")
        sni = self.get_env("REALITY_SNI", "www.microsoft.com")
        server_ip = self.get_env("SERVER_IP", "127.0.0.1")
        
        hysteria_pwd = self.get_env("HYSTERIA_PASSWORD")
        hysteria_obfs = self.get_env("HYSTERIA_OBFS_PASSWORD")
        hysteria_port = self.get_env("HYSTERIA_PORT", "443")
        
        if ":" in server_ip:
            uri_ip = f"[{server_ip}]"
        else:
            uri_ip = server_ip
            
        vless_link = f"vless://{vless_uuid}@{uri_ip}:443?type=tcp&security=reality&pbk={pub_key}&fp=chrome&sni={sni}&sid={short_id}&spx=%2F&flow=xtls-rprx-vision#VPN-VLESS-REALITY"
        hysteria_link = f"hysteria2://{hysteria_pwd}@{uri_ip}:{hysteria_port}?insecure=1&sni={sni}&obfs=salamander&obfs-password={hysteria_obfs}#VPN-Hysteria2"
        
        return [
            {"link": vless_link, "label": "VLESS + REALITY"},
            {"link": hysteria_link, "label": "Hysteria 2"}
        ]

    def create_backup(self):
        backup_dir = "/root/VPN-backups"
        os.makedirs(backup_dir, exist_ok=True)
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        backup_name = f"VPN-backup-{timestamp}"
        backup_path = os.path.join(backup_dir, backup_name)
        
        os.makedirs(backup_path, exist_ok=True)
        
        # .env
        shutil.copy(self.env_path, os.path.join(backup_path, ".env"))
        
        # hysteria2
        shutil.copytree(os.path.join(self.project_dir, "hysteria2"), os.path.join(backup_path, "hysteria2"), dirs_exist_ok=True)
        
        # fail2ban
        fail2ban_source = os.path.join(self.project_dir, "configs", "fail2ban")
        if os.path.exists(fail2ban_source):
            shutil.copytree(fail2ban_source, os.path.join(backup_path, "fail2ban"), dirs_exist_ok=True)
            
        # 3xui-db
        db_path_dest = os.path.join(backup_path, "3xui-db")
        os.makedirs(db_path_dest, exist_ok=True)
        subprocess.run(["docker", "run", "--rm", "-v", "3xui-db:/source:ro", "-v", f"{db_path_dest}:/backup", "alpine", "sh", "-c", "cp -a /source/* /backup/"], check=False)
        
        # Archive
        archive_path = f"{backup_path}.tar.gz"
        with tarfile.open(archive_path, "w:gz") as tar:
            tar.add(backup_path, arcname=os.path.basename(backup_path))
            
        shutil.rmtree(backup_path)
        
        # Clean old
        backups = sorted([os.path.join(backup_dir, f) for f in os.listdir(backup_dir) if f.endswith(".tar.gz")], key=os.path.getmtime)
        while len(backups) > 5:
            os.remove(backups.pop(0))
            
        return archive_path

    def restore_backup(self, archive_path):
        temp_dir = f"/tmp/VPN-restore-{int(datetime.now().timestamp())}"
        os.makedirs(temp_dir, exist_ok=True)
        
        with tarfile.open(archive_path, "r:gz") as tar:
            tar.extractall(path=temp_dir)
            
        inner_dirs = os.listdir(temp_dir)
        if not inner_dirs:
            raise Exception("Archive is empty")
        
        restore_src = os.path.join(temp_dir, inner_dirs[0])
        
        if os.path.exists(os.path.join(restore_src, ".env")):
            shutil.copy(os.path.join(restore_src, ".env"), self.env_path)
            
        if os.path.exists(os.path.join(restore_src, "hysteria2")):
            shutil.copytree(os.path.join(restore_src, "hysteria2"), os.path.join(self.project_dir, "hysteria2"), dirs_exist_ok=True)
            
        if os.path.exists(os.path.join(restore_src, "3xui-db")):
            subprocess.run(["docker", "volume", "create", "3xui-db"], check=False)
            subprocess.run(["docker", "run", "--rm", "-v", "3xui-db:/dest", "-v", f"{os.path.join(restore_src, '3xui-db')}:/source", "alpine", "sh", "-c", "cp -a /source/* /dest/"], check=False)
            
        if os.path.exists(os.path.join(restore_src, "fail2ban")):
            fail2ban_dest = os.path.join(self.project_dir, "configs", "fail2ban")
            os.makedirs(fail2ban_dest, exist_ok=True)
            shutil.copytree(os.path.join(restore_src, "fail2ban"), fail2ban_dest, dirs_exist_ok=True)
            
        shutil.rmtree(temp_dir)
        subprocess.run(["docker", "compose", "up", "-d", "--remove-orphans"], cwd=self.project_dir, check=False)

    def change_port(self, new_port):
        old_port = self.get_env("HYSTERIA_PORT", "443")
        self.set_env("HYSTERIA_PORT", str(new_port))
        
        # UFW
        subprocess.run(["ufw", "delete", "allow", f"{old_port}/udp"], check=False)
        subprocess.run(["ufw", "allow", f"{new_port}/udp", "comment", "Hysteria2 (Auto)"], check=False)
        
        # Reality inbound might be affected if SNI changes, but here we only changed Hysteria PORT
        # Hysteria Config update
        h2_config = os.path.join(self.project_dir, "hysteria2", "config.yaml")
        h2_template = f"{h2_config}.template"
        
        if os.path.exists(h2_template):
            with open(h2_template, 'r') as f:
                content = f.read()
            content = content.replace("__HYSTERIA_PASSWORD__", self.get_env("HYSTERIA_PASSWORD"))
            content = content.replace("__HYSTERIA_UP__", f"{self.get_env('HYSTERIA_UP_MBPS', '100')} mbps")
            content = content.replace("__HYSTERIA_DOWN__", f"{self.get_env('HYSTERIA_DOWN_MBPS', '100')} mbps")
            content = content.replace("__HYSTERIA_MASQUERADE__", self.get_env("REALITY_SNI", "www.microsoft.com"))
            content = content.replace("__HYSTERIA_OBFS_PASSWORD__", self.get_env("HYSTERIA_OBFS_PASSWORD", ""))
            content = content.replace("__HYSTERIA_PORT__", str(new_port))
            with open(h2_config, 'w') as f:
                f.write(content)
        else:
            if os.path.exists(h2_config):
                with open(h2_config, 'r') as f:
                    content = f.read()
                content = content.replace(f"listen: :{old_port}", f"listen: :{new_port}")
                with open(h2_config, 'w') as f:
                    f.write(content)
                    
        subprocess.run(["docker", "compose", "--env-file", ".env", "restart", "hysteria2"], cwd=self.project_dir, check=False)

    def change_xui_port(self, new_port):
        old_port = self.get_env("XUI_PORT", "2053")
        self.set_env("XUI_PORT", str(new_port))
        
        subprocess.run(["docker", "exec", "3x-ui", "/app/x-ui", "setting", "-port", str(new_port)], check=False)
        
        subprocess.run(["ufw", "allow", f"{new_port}/tcp", "comment", "3x-ui Panel (new)"], check=False)
        subprocess.run(["ufw", "delete", "allow", f"{old_port}/tcp"], check=False)
        
        jail_local = "/etc/fail2ban/jail.local"
        if os.path.exists(jail_local):
            with open(jail_local, 'r') as f:
                content = f.read()
            content = content.replace(f"port     = {old_port}", f"port     = {new_port}")
            with open(jail_local, 'w') as f:
                f.write(content)
            subprocess.run(["systemctl", "restart", "fail2ban"], check=False)
            
        subprocess.run(["docker", "restart", "3x-ui"], check=False)

    def update_geodata(self):
        geoip_url = "https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat"
        geosite_url = "https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat"
        
        subprocess.run(["docker", "exec", "3x-ui", "bash", "-c", 
            f"wget -O /usr/local/x-ui/bin/geoip.dat {geoip_url} && "
            f"wget -O /usr/local/x-ui/bin/geosite.dat {geosite_url} && "
            f"wget -O /usr/local/x-ui/bin/v2ray-rules-dat/geoip.dat {geoip_url} && "
            f"wget -O /usr/local/x-ui/bin/v2ray-rules-dat/geosite.dat {geosite_url}"
        ], check=True)
        
        subprocess.run(["docker", "restart", "3x-ui"], check=False)

if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser(description="VPN Manager")
    parser.add_argument("--generate-keys", action="store_true")
    parser.add_argument("--setup-inbound", action="store_true")
    parser.add_argument("--update-geodata", action="store_true")
    parser.add_argument("--show-clients", action="store_true")
    
    args = parser.parse_args()
    
    project_dir = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    manager = VPNManager(project_dir)
    
    if args.generate_keys:
        manager.generate_keys()
        print("Keys generated.")
    if args.setup_inbound:
        manager.setup_inbound()
        print("Inbound configured.")
    if args.update_geodata:
        manager.update_geodata()
        print("Geodata updated.")
    if args.show_clients:
        links = manager.get_client_links()
        for link in links:
            print(f"--- {link['label']} ---\n{link['link']}\n")
