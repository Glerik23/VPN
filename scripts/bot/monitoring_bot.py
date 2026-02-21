import os
import subprocess
import telebot
from telebot import types
import psutil
from dotenv import load_dotenv
import qrcode
from io import BytesIO

from vpn_manager import VPNManager

# Определяем пути относительно скрипта
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_DIR = os.path.dirname(os.path.dirname(SCRIPT_DIR))
ENV_PATH = os.path.join(PROJECT_DIR, '.env')

load_dotenv(ENV_PATH)

TOKEN = os.getenv('TG_BOT_TOKEN')
CHAT_ID = os.getenv('TG_CHAT_ID')

if not TOKEN:
    print("Error: TG_BOT_TOKEN not found in .env")
    exit(1)

bot = telebot.TeleBot(TOKEN)
manager = VPNManager(PROJECT_DIR)

def is_authorized(message):
    return str(message.chat.id) == str(CHAT_ID)

def get_stats():
    cpu = psutil.cpu_percent(interval=1)
    ram = psutil.virtual_memory().percent
    disk = psutil.disk_usage('/').percent
    return f"📊 <b>Статус сервера:</b>\n\n🔹 CPU: {cpu}%\n🔹 RAM: {ram}%\n🔹 Disk: {disk}%"

def get_main_keyboard():
    markup = types.ReplyKeyboardMarkup(row_width=2, resize_keyboard=True)
    markup.add(
        types.KeyboardButton('📊 Статус'),
        types.KeyboardButton('🔗 Ссылки'),
        types.KeyboardButton('🔄 Рестарт VPN'),
        types.KeyboardButton('💾 Бекап'),
        types.KeyboardButton('♻️ Сбросить ключи'),
        types.KeyboardButton('⚙️ Изменить порт Hysteria2'),
        types.KeyboardButton('🛡 Изменить порт Панели'),
        types.KeyboardButton('🌐 Обновить GeoData')
    )
    return markup

def handle_show_links(message):
    bot.send_message(message.chat.id, "⏳ Генерирую ссылки и QR-коды...")
    try:
        links = manager.get_client_links()
        
        if not links:
            bot.send_message(message.chat.id, "❌ Ссылки не найдены.")
            return

        for item in links:
            link = item['link']
            label = item['label']
            
            try:
                qr = qrcode.make(link)
                bio = BytesIO()
                qr.save(bio, format='PNG')
                bio.seek(0)
                
                bot.send_photo(
                    message.chat.id, 
                    bio, 
                    caption=f"🚀 <b>{label}</b>\n\n<code>{link}</code>", 
                    parse_mode='HTML'
                )
            except Exception as e:
                bot.send_message(message.chat.id, f"🔗 <b>{label}</b>:\n<code>{link}</code>", parse_mode='HTML')
                print(f"QR Error: {e}")

    except Exception as e:
        bot.send_message(message.chat.id, f"❌ Ошибка: {e}")

@bot.message_handler(commands=['start'])
def send_welcome(message):
    print(f"Received /start from {message.chat.id}")
    if not is_authorized(message):
        bot.reply_to(message, f"⛔ Доступ запрещен.\nВаш ID: {message.chat.id}\nПропишите его в TG_CHAT_ID в .env")
        return
    bot.send_message(message.chat.id, "👋 Привет! Я твой VPN помощник.", reply_markup=get_main_keyboard())

@bot.message_handler(func=lambda message: is_authorized(message), content_types=['text'])
def handle_message(message):
    if message.text == '📊 Статус':
        bot.send_message(message.chat.id, get_stats(), parse_mode='HTML')
    
    elif message.text == '🔗 Ссылки':
        handle_show_links(message)

    elif message.text == '🔄 Рестарт VPN':
        bot.send_message(message.chat.id, "🔄 Перезапускаю контейнеры...")
        try:
            subprocess.run(['docker', 'compose', '-f', os.path.join(PROJECT_DIR, 'docker-compose.yml'), 'restart'], check=True)
            bot.send_message(message.chat.id, "✅ Контейнеры перезапущены!")
        except Exception as e:
            bot.send_message(message.chat.id, f"❌ Ошибка рестарта: {e}")

    elif message.text == '♻️ Сбросить ключи':
        bot.send_message(message.chat.id, "⚠️ <b>Внимание!</b> Все старые ссылки перестанут работать.\n⏳ Начинаю ротацию ключей...", parse_mode='HTML')
        try:
            manager.generate_keys()
            manager.setup_inbound()
            subprocess.run(['docker', 'compose', '-f', os.path.join(PROJECT_DIR, 'docker-compose.yml'), 'restart'], check=True)
            
            bot.send_message(message.chat.id, "✅ Ключи успешно сброшены! Вот ваши новые ссылки:")
            handle_show_links(message)
        except Exception as e:
            bot.send_message(message.chat.id, f"❌ Ошибка при сбросе: {e}")

    elif message.text == '⚙️ Изменить порт Hysteria2':
        msg = bot.send_message(message.chat.id, "🔢 Введите новый UDP порт для Hysteria 2 (например, 39421):")
        bot.register_next_step_handler(msg, process_port_change)

    elif message.text == '🛡 Изменить порт Панели':
        msg = bot.send_message(message.chat.id, "🔢 Введите новый TCP порт для 3x-ui Panel (например, 2054):")
        bot.register_next_step_handler(msg, process_xui_port_change)

    elif message.text == '🌐 Обновить GeoData':
        bot.send_message(message.chat.id, "⏳ Обновляю GeoData для обхода блокировок...")
        try:
            manager.update_geodata()
            bot.send_message(message.chat.id, "✅ GeoData обновлена и Xray перезапущен!")
        except Exception as e:
            bot.send_message(message.chat.id, f"❌ Ошибка при обновлении GeoData: {e}")

    elif message.text == '💾 Бекап':
        bot.send_message(message.chat.id, "💾 Создаю бекап...")
        try:
            archive_path = manager.create_backup()
            with open(archive_path, 'rb') as f:
                bot.send_document(message.chat.id, f, caption="📦 Полный бекап VPN сервера (.tar.gz)")
            # Cleanup sent backup to save space if needed
            # os.remove(archive_path) 
        except Exception as e:
            bot.send_message(message.chat.id, f"❌ Ошибка бекапа: {e}")

def process_port_change(message):
    if not is_authorized(message): return
    
    new_port = message.text.strip()
    if not new_port.isdigit() or not (1 <= int(new_port) <= 65535):
        bot.send_message(message.chat.id, "❌ Ошибка: введите корректное число (1-65535)")
        return
    
    bot.send_message(message.chat.id, f"⏳ Меняю порт Hysteria2 на {new_port}...")
    try:
        manager.change_port(new_port)
        bot.send_message(message.chat.id, f"✅ Порт изменен на {new_port}! Вот ваши новые ссылки:")
        handle_show_links(message)
    except Exception as e:
        bot.send_message(message.chat.id, f"❌ Ошибка при смене порта: {e}")

def process_xui_port_change(message):
    if not is_authorized(message): return
    
    new_port = message.text.strip()
    if not new_port.isdigit() or not (1024 <= int(new_port) <= 65535):
        bot.send_message(message.chat.id, "❌ Ошибка: введите корректное число (1024-65535)")
        return
    
    bot.send_message(message.chat.id, f"⏳ Меняю порт Панели на {new_port}...")
    try:
        manager.change_xui_port(new_port)
        bot.send_message(message.chat.id, f"✅ Порт Панели изменен на {new_port}! Старый порт больше недоступен.")
    except Exception as e:
        bot.send_message(message.chat.id, f"❌ Ошибка при смене порта Панели: {e}")

@bot.message_handler(func=lambda message: is_authorized(message), content_types=['document'])
def handle_document_restore(message):
    if message.document.file_name.endswith('.tar.gz') and 'VPN-backup' in message.document.file_name:
        bot.send_message(message.chat.id, "⏳ Обнаружен архив бэкапа. Начинаю восстановление...")
        try:
            file_info = bot.get_file(message.document.file_id)
            downloaded_file = bot.download_file(file_info.file_path)
            
            temp_path = f"/tmp/{message.document.file_name}"
            with open(temp_path, 'wb') as new_file:
                new_file.write(downloaded_file)
            
            manager.restore_backup(temp_path)
            os.remove(temp_path)
            
            bot.send_message(message.chat.id, "✅ Восстановление успешно завершено! Контейнеры запущены.")
        except Exception as e:
            bot.send_message(message.chat.id, f"❌ Ошибка при восстановлении: {e}")
    else:
        bot.send_message(message.chat.id, "⚠️ Документ не похож на бэкап VPN (ожидается VPN-backup...tar.gz).")

@bot.message_handler(func=lambda message: True)
def handle_unauthorized(message):
    print(f"Unauthorized message from {message.chat.id}: {message.text}")
    bot.reply_to(message, "⛔ Доступ запрещен. Я работаю только с владельцем.")

if __name__ == "__main__":
    print("Bot started...")
    # Очищаем вебхук, если он был установлен ранее (решает ошибку 409 Conflict)
    bot.remove_webhook()
    bot.polling(none_stop=True)
