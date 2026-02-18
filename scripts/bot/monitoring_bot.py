import os
import subprocess
import telebot
from telebot import types
import psutil
from dotenv import load_dotenv

# Загрузка .env
ENV_PATH = '/root/vpn/.env'
load_dotenv(ENV_PATH)

TOKEN = os.getenv('TG_BOT_TOKEN')
CHAT_ID = os.getenv('TG_CHAT_ID')

if not TOKEN:
    print("Error: TG_BOT_TOKEN not found in .env")
    exit(1)

bot = telebot.TeleBot(TOKEN)

def is_authorized(message):
    return str(message.chat.id) == str(CHAT_ID)

def get_stats():
    cpu = psutil.cpu_percent(interval=1)
    ram = psutil.virtual_memory().percent
    disk = psutil.disk_usage('/').percent
    return f"📊 <b>Статус сервера:</b>\n\n🔹 CPU: {cpu}%\n🔹 RAM: {ram}%\n🔹 Disk: {disk}%"

def get_main_keyboard():
    markup = types.ReplyKeyboardMarkup(row_width=2, resize_keyboard=True)
    btn_status = types.KeyboardButton('📊 Статус')
    btn_clients = types.KeyboardButton('🔗 Ссылки')
    btn_restart = types.KeyboardButton('🔄 Рестарт VPN')
    btn_backup = types.KeyboardButton('💾 Бекап')
    markup.add(btn_status, btn_clients, btn_restart, btn_backup)
    return markup

@bot.message_handler(func=lambda message: is_authorized(message), content_types=['text'])
def handle_message(message):
    if message.text == '📊 Статус':
        bot.send_message(message.chat.id, get_stats(), parse_mode='HTML')
    
    elif message.text == '🔗 Ссылки':
        bot.send_message(message.chat.id, "⏳ Получаю ссылки...")
        try:
            res = subprocess.check_output(['/root/vpn/scripts/05-show-clients.sh'], stderr=subprocess.STDOUT).decode()
            # Убираем лишние ANSI цвета из вывода для TG
            clean_res = res.replace('\033[0;32m', '').replace('\033[0m', '').replace('\033[0;36m', '').replace('\033[0;31m', '')
            bot.send_message(message.chat.id, f"<code>{clean_res}</code>", parse_mode='HTML')
        except Exception as e:
            bot.send_message(message.chat.id, f"❌ Ошибка: {e}")

    elif message.text == '🔄 Рестарт VPN':
        bot.send_message(message.chat.id, "🔄 Перезапускаю контейнеры...")
        try:
            subprocess.run(['docker', 'compose', '-f', '/root/vpn/docker-compose.yml', 'restart'], check=True)
            bot.send_message(message.chat.id, "✅ Контейнеры перезапущены!")
        except Exception as e:
            bot.send_message(message.chat.id, f"❌ Ошибка рестарта: {e}")

    elif message.text == '💾 Бекап':
        bot.send_message(message.chat.id, "💾 Создаю бекап...")
        try:
            # Просто отправляем .env и x-ui.db (если доступен)
            with open(ENV_PATH, 'rb') as f:
                bot.send_document(message.chat.id, f, caption="🔐 Файл .env")
            
            db_path = "/var/lib/docker/volumes/3xui-db/_data/x-ui.db"
            if os.path.exists(db_path):
                with open(db_path, 'rb') as f:
                    bot.send_document(message.chat.id, f, caption="📦 База данных x-ui.db")
            else:
                bot.send_message(message.chat.id, "⚠️ Файл БД не найден по стандартному пути.")
        except Exception as e:
            bot.send_message(message.chat.id, f"❌ Ошибка бекапа: {e}")

@bot.message_handler(commands=['start'])
def send_welcome(message):
    if not is_authorized(message):
        bot.reply_to(message, f"⛔ Доступ запрещен.\nВаш ID: {message.chat.id}\nПропишите его в TG_CHAT_ID в .env")
        return
    bot.send_message(message.chat.id, "👋 Привет! Я твой VPN помощник.", reply_markup=get_main_keyboard())

@bot.message_handler(func=lambda message: True)
def handle_unauthorized(message):
    bot.reply_to(message, "⛔ Доступ запрещен. Я работаю только с владельцем.")

if __name__ == "__main__":
    print("Bot started...")
    bot.polling(none_stop=True)
