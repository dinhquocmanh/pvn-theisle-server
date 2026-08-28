# prompt 1
Bạn hãy hoàn thiện docker compose project này cho tôi
Project này dùng để chạy TheIsle Server Evrima
Đầu tiên đây là draft project chưa hoàn thiện.
Hãy sửa file .env.example cho chuẩn format. Cái nào trùng thì bỏ đi
Sau đó viết nốt các file còn lại.
Tôi muốn toàn bộ project này run dưới user ubuntu và mount ra thư mục data/

# Cách cài default settings cho game:
mỗi lần start game các settings trong env sẽ ghi đè vào file Game.ini. Cấu trúc tham khảo ở configs/DefaultGame.ini
pvn-theisle-server/data/TheIsle/Saved/Config/LinuxServer/Game.ini


# Cách tải 2 Mods cần thiết:
cd data/TheIsle/Binaries/Linux
curl https://islepilot.eu/cdn/plugin/libisleplugin.so -o libisleplugin.so
curl https://cdn.isle-voip.com/server/linux/TheIsleProxPlugin.so -o TheIsleProxPlugin.so

Tải hai file trên và lưu vào thư mục trên. Sau đó sửa file:
pvn-theisle-server/data/TheIsle/Binaries/Linux/islepilot-config.json
thay api key: "apiKey": "ipk_ef68256daaa8a70343b07e5690c3xxxx"
/home/ubuntu/workspace/pvn-theisle-server/data/TheIsle/Binaries/Linux/settings.json
thay api key: "server_hash": "a6bae0b697431a942098c9b10f926d6aa6588106"

# Tôi muốn mỗi lần start thì gửi message lên webhook: Server name Started.

# Backup:
Mỗi 30 phút 1 lần backup toàn bộ pvn-theisle-server/data/TheIsle/Saved/PlayerData vào data/backup
Mỗi 30 phút 1 lần backup toàn bộ jsons trong thư mục pvn-theisle-server/data/TheIsle/Binaries/Linux vào data/backup
Backup quá 5 ngày tự động xoá đi.

# tính năng log
cứ mỗi 2 giây read log ở file dưới và gửi lên webhook nếu LOG_WEBHOOK được set.
Logfile hãy viết file scripts/discord_log.py để handle
Có tính năng lọc chỉ những message join, leave, kill, death. còn lại ko cần send.
/home/ubuntu/workspace/theisle-server/data/TheIsle/Saved/Logs/TheIsle.log