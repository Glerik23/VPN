import os
import subprocess
import telebot
from telebot import types
import psutil
from dotenv import load_dotenv

# Определение путей относительно скрипта
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_DIR = os.path.dirname(SCRIPT_DIR)
ENV_PATH = os.path.join(PROJECT_DIR, '.env')

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
    btn_port = types.KeyboardButton('⚙️ Изменить порт')
    markup.add(btn_status, btn_clients, btn_restart, btn_backup, btn_reset, btn_port)
    return markup

def handle_show_links(message):
    bot.send_message(message.chat.id, "⏳ Генерирую ссылки и QR-коды...")
    try:
        # Выполняем скрипт с новым флагом --links-only
        res = subprocess.check_output(
            [os.path.join(PROJECT_DIR, 'scripts', '05-show-clients.sh'), '--links-only'], 
            stderr=subprocess.STDOUT
        ).decode()
        
        # Разделяем по строкам и фильтруем пустые
        links = [l.strip() for l in res.split('\n') if l.strip()]
        
        all_links = []
        for l in links:
            if l.startswith('vless://'):
                all_links.append((l, "VLESS + REALITY"))
            elif l.startswith('hysteria2://'):
                all_links.append((l, "Hysteria 2"))
        
        if not all_links:
            bot.send_message(message.chat.id, "❌ Ссылки не найдены. Сначала запустите скрипты настройки.")
            return

        for i, (link, label) in enumerate(all_links):
            qr_path = f"/tmp/qr_{i}.png"
            try:
                # Генерация QR
                subprocess.run(['qrencode', '-o', qr_path, '-s', '10', link], check=True)
                
                with open(qr_path, 'rb') as photo:
                    bot.send_photo(
                        message.chat.id, 
                        photo, 
                        caption=f"🚀 <b>{label}</b>\n\n<code>{link}</code>", 
                        parse_mode='HTML'
                    )
                if os.path.exists(qr_path):
                    os.remove(qr_path)
            except Exception as qr_err:
                bot.send_message(message.chat.id, f"🔗 <b>{label}</b>:\n<code>{link}</code>", parse_mode='HTML')

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
            subprocess.run(['docker', 'compose', '-f', '/root/VPN/docker-compose.yml', 'restart'], check=True)
            bot.send_message(message.chat.id, "✅ Контейнеры перезапущены!")
        except Exception as e:
            bot.send_message(message.chat.id, f"❌ Ошибка рестарта: {e}")

    elif message.text == '♻️ Сбросить ключи':
        bot.send_message(message.chat.id, "⚠️ <b>Внимание!</b> Все старые ссылки перестанут работать.\n⏳ Начинаю ротацию ключей...", parse_mode='HTML')
        try:
            # 1. Генерируем новые ключи в .env
            subprocess.run([os.path.join(PROJECT_DIR, 'scripts', '04-generate-keys.sh')], check=True)
            # 2. Обновляем панель 3x-ui
            subprocess.run([os.path.join(PROJECT_DIR, 'scripts', '08-setup-inbound.sh')], check=True)
            # 3. Перезапускаем контейнеры
            subprocess.run(['docker', 'compose', '-f', os.path.join(PROJECT_DIR, 'docker-compose.yml'), 'restart'], check=True)
            
            bot.send_message(message.chat.id, "✅ Ключи успешно сброшены! Вот ваши новые ссылки:")
            handle_show_links(message)
        except Exception as e:
            bot.send_message(message.chat.id, f"❌ Ошибка при сбросе: {e}")

    elif message.text == '⚙️ Изменить порт':
        msg = bot.send_message(message.chat.id, "🔢 Введите новый UDP порт для Hysteria 2 (например, 39421):")
        bot.register_next_step_handler(msg, process_port_change)

    elif message.text == '💾 Бекап':
        bot.send_message(message.chat.id, "💾 Создаю бекап...")
        try:
            # Просто отправляем .env и x-ui.db (если доступен)
            with open(ENV_PATH, 'rb') as f:
                bot.send_document(message.chat.id, f, caption="🔐 Файл .env")
            
            # Попытка найти базу данных через docker inspect
            try:
                volume_info = subprocess.check_output(['docker', 'volume', 'inspect', '3xui-db']).decode()
                import json
                volume_data = json.loads(volume_info)
                mount_point = volume_data[0]['Mountpoint']
                db_path = os.path.join(mount_point, 'x-ui.db')
                
                if os.path.exists(db_path):
                    with open(db_path, 'rb') as f:
                        bot.send_document(message.chat.id, f, caption="📦 База данных x-ui.db")
                else:
                    # Если прямой доступ к /var/lib/docker закрыт, пробуем через docker cp
                    bot.send_message(message.chat.id, "⏳ Копирую БД из контейнера...")
                    subprocess.run(['docker', 'cp', '3x-ui:/etc/x-ui/x-ui.db', '/tmp/x-ui.db'], check=True)
                    with open('/tmp/x-ui.db', 'rb') as f:
                        bot.send_document(message.chat.id, f, caption="📦 База данных x-ui.db (из контейнера)")
                    os.remove('/tmp/x-ui.db')
            except Exception as db_err:
                bot.send_message(message.chat.id, f"⚠️ Не удалось получить БД: {db_err}")
        except Exception as e:
            bot.send_message(message.chat.id, f"❌ Ошибка бекапа: {e}")

def process_port_change(message):
    if not is_authorized(message): return
    
    new_port = message.text.strip()
    if not new_port.isdigit() or not (1 <= int(new_port) <= 65535):
        bot.send_message(message.chat.id, "❌ Ошибка: введите корректное число (1-65535)")
        return
    
    bot.send_message(message.chat.id, f"⏳ Меняю порт на {new_port}...")
    try:
        # Вызываем скрипт с новым портом и ловим ошибки
        result = subprocess.run(
            [os.path.join(PROJECT_DIR, 'scripts', '11-change-port.sh'), new_port], 
            capture_output=True, 
            text=True, 
            check=True
        )
        bot.send_message(message.chat.id, f"✅ Порт изменен на {new_port}! Вот ваши новые ссылки:")
        handle_show_links(message)
    except subprocess.CalledProcessError as e:
        error_msg = f"❌ Ошибка при смене порта:\n<code>{e.stderr}</code>"
        bot.send_message(message.chat.id, error_msg, parse_mode='HTML')
    except Exception as e:
        bot.send_message(message.chat.id, f"❌ Непредвиденная ошибка: {e}")

@bot.message_handler(func=lambda message: True)
def handle_unauthorized(message):
    print(f"Unauthorized message from {message.chat.id}: {message.text}")
    bot.reply_to(message, "⛔ Доступ запрещен. Я работаю только с владельцем.")

if __name__ == "__main__":
    print("Bot started...")
    # Очищаем вебхук, если он был установлен ранее (решает ошибку 409 Conflict)
    bot.remove_webhook()
    bot.polling(none_stop=True)
