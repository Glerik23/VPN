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
    btn_reset = types.KeyboardButton('♻️ Сбросить ключи')
    markup.add(btn_status, btn_clients, btn_restart, btn_backup, btn_reset)
    return markup

def handle_show_links(message):
    bot.send_message(message.chat.id, "⏳ Генерирую ссылки и QR-коды...")
    try:
        # Выполняем скрипт для получения текста
        res = subprocess.check_output(['/root/vpn/scripts/05-show-clients.sh'], stderr=subprocess.STDOUT).decode()
        
        import re
        # Находим все ссылки vless:// и hysteria2://
        links = re.findall(r'(vless://[^\s\x1b]+|hysteria2://[^\s\x1b]+)', res)
        
        if not links:
            bot.send_message(message.chat.id, "❌ Ссылки не найдены. Сначала запустите скрипты настройки.")
            return

        for i, link in enumerate(links):
            # Название для файла
            qr_path = f"/tmp/qr_{i}.png"
            # Генерация QR через qrencode
            try:
                subprocess.run(['qrencode', '-o', qr_path, '-s', '10', link], check=True)
                
                # Определяем тип для подписи
                label = "VLESS + REALITY" if "vless" in link else "Hysteria 2"
                
                with open(qr_path, 'rb') as photo:
                    bot.send_photo(
                        message.chat.id, 
                        photo, 
                        caption=f"🚀 <b>{label}</b>\n\n<code>{link}</code>", 
                        parse_mode='HTML'
                    )
                # Удаляем временный файл
                if os.path.exists(qr_path):
                    os.remove(qr_path)
            except Exception as qr_err:
                print(f"QR Error: {qr_err}")
                bot.send_message(message.chat.id, f"🔗 <code>{link}</code>", parse_mode='HTML')

    except Exception as e:
        bot.send_message(message.chat.id, f"❌ Ошибка: {e}")

@bot.message_handler(commands=['start'])
def send_welcome(message):
    print(f"Received /start from {message.chat.id}")
    if not is_authorized(message):
        print(f"Unauthorized access attempt by {message.chat.id}")
        bot.reply_to(message, f"⛔ Доступ запрещен.\nВаш ID: {message.chat.id}\nПропишите его в TG_CHAT_ID в .env")
        return
    bot.send_message(message.chat.id, "👋 Привет! Я твой VPN помощник.", reply_markup=get_main_keyboard())

@bot.message_handler(func=lambda message: is_authorized(message), content_types=['text'])
def handle_message(message):
    print(f"Received message: {message.text} from {message.chat.id}")
    if message.text == '📊 Статус':
        bot.send_message(message.chat.id, get_stats(), parse_mode='HTML')
    
    elif message.text == '🔗 Ссылки':
        handle_show_links(message)

    elif message.text == '🔄 Рестарт VPN':
        bot.send_message(message.chat.id, "🔄 Перезапускаю контейнеры...")
        try:
            subprocess.run(['docker', 'compose', '-f', '/root/vpn/docker-compose.yml', 'restart'], check=True)
            bot.send_message(message.chat.id, "✅ Контейнеры перезапущены!")
        except Exception as e:
            bot.send_message(message.chat.id, f"❌ Ошибка рестарта: {e}")

    elif message.text == '♻️ Сбросить ключи':
        bot.send_message(message.chat.id, "⚠️ <b>Внимание!</b> Все старые ссылки перестанут работать.\n⏳ Начинаю ротацию ключей...", parse_mode='HTML')
        try:
            # 1. Генерируем новые ключи в .env
            subprocess.run(['/root/vpn/scripts/04-generate-keys.sh'], check=True)
            # 2. Обновляем панель 3x-ui
            subprocess.run(['/root/vpn/scripts/08-setup-inbound.sh'], check=True)
            # 3. Перезапускаем контейнеры
            subprocess.run(['docker', 'compose', '-f', '/root/vpn/docker-compose.yml', 'restart'], check=True)
            
            bot.send_message(message.chat.id, "✅ Ключи успешно сброшены! Вот ваши новые ссылки:")
            handle_show_links(message)
        except Exception as e:
            bot.send_message(message.chat.id, f"❌ Ошибка при сбросе: {e}")

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

@bot.message_handler(func=lambda message: True)
def handle_unauthorized(message):
    print(f"Unauthorized message from {message.chat.id}: {message.text}")
    bot.reply_to(message, "⛔ Доступ запрещен. Я работаю только с владельцем.")

if __name__ == "__main__":
    print("Bot started...")
    # Очищаем вебхук, если он был установлен ранее (решает ошибку 409 Conflict)
    bot.remove_webhook()
    bot.polling(none_stop=True)
