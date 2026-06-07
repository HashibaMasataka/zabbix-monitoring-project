#!/bin/bash
# ====================================================================
# 文化祭 NOCプロジェクト: Zabbix 7.0 LTS 自動構築スクリプト (Ubuntu 24.04用)
# ====================================================================

set -e # エラーが発生したらその時点で処理を中断する安全装置

echo "=== [1/6] OSのアップデートと前提パッケージの導入 ==="
sudo apt-get update && sudo apt-get upgrade -y
sudo apt-get install -y lsb-release ca-certificates curl gnupg

echo "=== [2/6] Zabbix 7.0 公式リポジトリの登録 ==="
# Ubuntu 24.04 (noble) 用の公式パッケージを登録
wget https://repo.zabbix.com/zabbix/7.0/ubuntu/pool/main/z/zabbix-release/zabbix-release_7.0-1+ubuntu24.04_all.deb
sudo dpkg -i zabbix-release_7.0-1+ubuntu24.04_all.deb
sudo apt-get update

echo "=== [3/6] Zabbix本体・Apache・MariaDB(データベース)のインストール ==="
# 容量不足によるインストール漏れを防ぐため、一気に関連パッケージを導入
sudo apt-get install -y zabbix-server-mysql zabbix-frontend-php zabbix-apache-conf zabbix-agent mariadb-server

echo "=== [4/6] データベースの初期設定と部屋作成 ==="
# データベースのスイッチをオン
sudo systemctl start mariadb
sudo systemctl enable mariadb

# Zabbix用のデータベース、ユーザー(パスワード: ???????)を作成
sudo mysql -uroot -e "CREATE DATABASE zabbix CHARACTER SET utf8mb4 COLLATE utf8mb4_bin;"
sudo mysql -uroot -e "CREATE USER 'zabbix'@'localhost' IDENTIFIED BY 'ConvPass00';"
sudo mysql -uroot -e "GRANT ALL PRIVILEGES ON zabbix.* TO 'zabbix'@'localhost';"
sudo mysql -uroot -e "SET GLOBAL log_bin_trust_function_creators = 1;"

echo "=== [5/6] Zabbix初期データの流し込み (少々時間がかかります) ==="
# データベースに数万行の初期スキーマをインポート
zcat /usr/share/zabbix-sql-scripts/mysql/server.sql.gz | mysql --default-character-set=utf8mb4 -uzabbix -p'ConvPass00' zabbix

# インポート完了後、安全のためにデータベースの作成モードを終了
sudo mysql -uroot -e "SET GLOBAL log_bin_trust_function_creators = 0;"

echo "=== [6/6] Zabbix設定ファイルの編集とセキュリティ暗号化(HTTPS化) ==="
# 設定ファイルにデータベースのパスワードを書き込む
sudo sed -i 's/# DBPassword=/DBPassword=ConvPass00/g' /etc/zabbix/zabbix_server.conf

# サーバーのIPアドレスを自動取得
SERVER_IP=$(hostname -I | awk '{print $1}')

# 3650日(10年間)有効な自己署名証明書(SSL鍵)を生成
sudo openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
  -keyout /etc/ssl/private/zabbix-selfsigned.key \
  -out /etc/ssl/certs/zabbix-selfsigned.crt \
  -subj "/CN=${SERVER_IP}"

# ApacheのSSLモジュールとデフォルトHTTPSサイトを有効化
sudo a2enmod ssl
sudo a2ensite default-ssl

# Apacheの設定ファイルに、今作ったSSL鍵の場所を教える
sudo sed -i "s|SSLCertificateFile.*|SSLCertificateFile /etc/ssl/certs/zabbix-selfsigned.crt|g" /etc/apache2/sites-available/default-ssl.conf
sudo sed -i "s|SSLCertificateKeyFile.*|SSLCertificateKeyFile /etc/ssl/private/zabbix-selfsigned.key|g" /etc/apache2/sites-available/default-ssl.conf

echo "=== [完了] すべてのサービスを起動・自動起動登録します ==="
sudo systemctl restart zabbix-server zabbix-agent apache2
sudo systemctl enable zabbix-server zabbix-agent apache2

echo "--------------------------------------------------------"
echo " 🎉 Zabbix 7.0 サーバーの土台構築が完了しました！"
echo " 以下のURLからPCのブラウザでアクセスしてください（警告は続行してOK）"
echo " URL: https://${SERVER_IP}/zabbix"
echo "--------------------------------------------------------"
