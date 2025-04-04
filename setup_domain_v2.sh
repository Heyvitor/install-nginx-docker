#!/bin/bash

# Verificar se é root
if [ "$(id -u)" -ne 0 ]; then
  echo "Execute este script como root ou com sudo"
  exit 1
fi

# Menu de seleção
echo "Selecione o tipo de aplicação:"
echo "1) Laravel"
echo "2) Node.js/Express"
echo "3) N8N - Docker"
read -p "Opção (1/2/3): " APP_TYPE

if [ "$APP_TYPE" != "1" ] && [ "$APP_TYPE" != "2" ] && [ "$APP_TYPE" != "3" ]; then
  echo "Opção inválida"
  exit 1
fi

# Pedir domínio e email após seleção do tipo
if [ "$APP_TYPE" == "3" ]; then
  read -p "Digite o domínio para o N8N (ex: n8n.meusite.com): " N8N_HOST
  DOMINIO=$N8N_HOST
else
  read -p "Digite o domínio (ex: meusite.com): " DOMINIO
fi
read -p "Digite o email para SSL [opcional, padrão admin@$DOMINIO]: " EMAIL_INPUT
EMAIL=${EMAIL_INPUT:-admin@$DOMINIO}

# Configuração específica por tipo
if [ "$APP_TYPE" == "1" ]; then
  read -p "Digite o caminho completo para a pasta public do Laravel: " LARAVEL_PATH
  if [ ! -d "$LARAVEL_PATH" ]; then
    echo "Pasta não encontrada: $LARAVEL_PATH"
    exit 1
  fi
elif [ "$APP_TYPE" == "2" ]; then
  read -p "Digite a porta do servidor Node.js: " PORTA
  if ! [[ "$PORTA" =~ ^[0-9]+$ ]]; then
    echo "Porta inválida"
    exit 1
  fi
elif [ "$APP_TYPE" == "3" ]; then
  N8N_PORT=5678
  GENERIC_TIMEZONE="America/Sao_Paulo"
  
  # Criar diretório para o N8N
  N8N_DIR="/opt/n8n"
  sudo mkdir -p $N8N_DIR
  cd $N8N_DIR
  
  # Criar docker-compose.yml com variáveis fixas
  sudo tee docker-compose.yml > /dev/null <<EOL
version: "3.8"
services:
  n8n:
    image: docker.n8n.io/n8nio/n8n:1.86.0
    restart: always
    environment:
      - N8N_HOST=$N8N_HOST
      - N8N_PORT=5678
      - N8N_PROTOCOL=https
      - NODE_ENV=production
      - WEBHOOK_URL=https://$N8N_HOST/
      - GENERIC_TIMEZONE=America/Sao_Paulo
      - N8N_SECURE_COOKIE=false
      - N8N_RUNNERS_ENABLED=true
      - N8N_ENFORCE_SETTINGS_FILE_PERMISSIONS=true
    volumes:
      - n8n_data:/home/node/.n8n
    ports:
      - "5678:5678"
volumes:
  n8n_data:
EOL

  # Iniciar o Docker Compose
  sudo docker-compose up -d
fi

# Instalar Certbot se não existir
if ! command -v certbot &> /dev/null; then
  echo "Instalando Certbot para SSL..."
  sudo apt install -y certbot python3-certbot-nginx
fi

# Criar configuração Nginx
CONF_FILE="/etc/nginx/sites-available/$DOMINIO"

if [ "$APP_TYPE" == "1" ]; then
  sudo tee $CONF_FILE > /dev/null <<EOL
server {
    listen 80;
    server_name $DOMINIO www.$DOMINIO;
    root $LARAVEL_PATH;
    index index.php index.html index.htm;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/var/run/php/php-fpm.sock;
    }

    location ~ /\.ht {
        deny all;
    }
}
EOL
elif [ "$APP_TYPE" == "2" ]; then
  sudo tee $CONF_FILE > /dev/null <<EOL
server {
    listen 80;
    server_name $DOMINIO www.$DOMINIO;

    location / {
        proxy_pass http://localhost:$PORTA;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_cache_bypass \$http_upgrade;
    }
}
EOL
elif [ "$APP_TYPE" == "3" ]; then
  sudo tee $CONF_FILE > /dev/null <<EOL
server {
    listen 80;
    server_name $DOMINIO;

    location / {
        proxy_pass http://localhost:5678;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_cache_bypass \$http_upgrade;
    }
}
EOL
fi

# Habilitar site
sudo ln -sf $CONF_FILE /etc/nginx/sites-enabled/
sudo nginx -t && sudo systemctl reload nginx

# Verificar DNS antes de tentar SSL
echo "Verificando configuração DNS para $DOMINIO..."

# Obter todos IPs do servidor (IPv4 e IPv6)
SERVER_IP4=$(curl -4 -s ifconfig.me)
SERVER_IP6=$(curl -6 -s ifconfig.me || echo "")
DOMAIN_IP4=$(dig +short A $DOMINIO | tail -n1)
DOMAIN_IP6=$(dig +short AAAA $DOMINIO | tail -n1)

# Verificar se algum IP coincide
DNS_OK=false
if [ -n "$DOMAIN_IP4" ] && { [ "$DOMAIN_IP4" == "$SERVER_IP4" ] || [ "$DOMAIN_IP4" == "$SERVER_IP6" ]; }; then
  DNS_OK=true
elif [ -n "$DOMAIN_IP6" ] && { [ "$DOMAIN_IP6" == "$SERVER_IP4" ] || [ "$DOMAIN_IP6" == "$SERVER_IP6" ]; }; then
  DNS_OK=true
fi

if ! $DNS_OK; then
  echo "AVISO: O domínio $DOMINIO não está apontando para este servidor"
  echo "       IPs do servidor: IPv4=$SERVER_IP4, IPv6=$SERVER_IP6"
  echo "       IPs do domínio: IPv4=$DOMAIN_IP4, IPv6=$DOMAIN_IP6"
  read -p "Deseja tentar obter SSL mesmo assim? [s/N] " SSL_TRY
  
  if [[ ! "$SSL_TRY" =~ ^[sS] ]]; then
    echo "Pulando configuração SSL..."
    SSL_SUCCESS=false
  else
    echo "Tentando obter certificado SSL apenas para $DOMINIO (sem www)..."
    sudo certbot --nginx -d $DOMINIO --non-interactive --agree-tos -m $EMAIL
    SSL_SUCCESS=$?
  fi
else
  # Verificar se www existe
  WWW_IP4=$(dig +short A www.$DOMINIO | tail -n1)
  WWW_IP6=$(dig +short AAAA www.$DOMINIO | tail -n1)
  
  if [ -n "$WWW_IP4" ] || [ -n "$WWW_IP6" ]; then
    echo "Obtendo certificado SSL para $DOMINIO e www.$DOMINIO..."
    sudo certbot --nginx -d $DOMINIO -d www.$DOMINIO --non-interactive --agree-tos -m $EMAIL
  else
    echo "Obtendo certificado SSL apenas para $DOMINIO (www não configurado)..."
    sudo certbot --nginx -d $DOMINIO --non-interactive --agree-tos -m $EMAIL
  fi
  SSL_SUCCESS=$?
fi

# Configurar renovação automática se SSL foi bem sucedido
if [ $SSL_SUCCESS -eq 0 ]; then
  (crontab -l 2>/dev/null; echo "0 12 * * * /usr/bin/certbot renew --quiet") | crontab -
else
  echo "AVISO: Não foi configurado SSL automático devido a falha na verificação"
fi

echo "Configuração concluída!"
if [ $SSL_SUCCESS -eq 0 ]; then
  echo "Domínio: https://$DOMINIO"
else
  echo "Domínio: http://$DOMINIO (SSL não configurado)"
fi

if [ "$APP_TYPE" == "1" ]; then
  echo "Laravel configurado na pasta: $LARAVEL_PATH"
elif [ "$APP_TYPE" == "2" ]; then
  echo "Proxy configurado para porta: $PORTA"
elif [ "$APP_TYPE" == "3" ]; then
  echo "N8N configurado via Docker no domínio: $DOMINIO"
fi