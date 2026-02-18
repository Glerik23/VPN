import os
import time
import psutil
import requests
from dotenv import load_dotenv

# Загрузка .env
load_dotenv('/root/vpn/.env')

TOKEN = os.getenv('TG_BOT_TOKEN')
CHAT_ID = os.getenv('TG_CHAT_ID')

def send_msg(text):
    if not TOKEN or not CHAT_ID:
        return
    url = f"https://api.telegram.org/bot{TOKEN}/sendMessage"
    try:
        requests.post(url, json={"chat_id": CHAT_ID, "text": text, "parse_mode": "HTML"})
    except Exception as e:
        print(f"Error sending to TG: {e}")

def get_stats():
    cpu = psutil.cpu_percent(interval=1)
    ram = psutil.virtual_memory().percent
    disk = psutil.disk_usage('/').percent
    return f"📊 <b>Статус сервера:</b>\n\n🔹 CPU: {cpu}%\n🔹 RAM: {ram}%\n🔹 Disk: {disk}%"

def check_fail2ban():
    # Простой парсинг логов fail2ban (для примера)
    # В реальности лучше использовать fail2ban-client
    pass

if __name__ == "__main__":
    # При запуске отправляем статус
    send_msg(f"🚀 <b>Мониторинг активирован!</b>\n\n{get_stats()}")
