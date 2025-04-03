#!/bin/bash

# Verificar se é root
if [ "$(id -u)" -ne 0 ]; then
  echo "Execute este script como root ou com sudo"
  exit 1
fi

# Verificar parâmetros
if [ $# -lt 2 ]; then
  echo "Uso: $0 <dominio> <porta_container> [email_para_ssl]"
  echo "Exemplo: $0 meusite.com 3000 contato@meusite.com"
  exit 1
fi

DOMINIO=$1
PORTA=$2
EMAIL=${3:-admin@$DOMINIO}

# Instalar Certbot se não existir
if ! command -v certbot &> /dev/null; then
  echo "Instalando Certbot para SSL..."
  sudo apt install -y certbot python3-certbot-nginx
fi

# Criar configuração Nginx
CONF_FILE="/etc/nginx/sites-available/$DOMINIO"
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

# Habilitar site
sudo ln -sf $CONF_FILE /etc/nginx/sites-enabled/
sudo nginx -t && sudo systemctl reload nginx

# Obter certificado SSL
echo "Obtendo certificado SSL para $DOMINIO..."
sudo certbot --nginx -d $DOMINIO -d www.$DOMINIO --non-interactive --agree-tos -m $EMAIL

# Configurar renovação automática
(crontab -l 2>/dev/null; echo "0 12 * * * /usr/bin/certbot renew --quiet") | crontab -

echo "Configuração concluída!"
echo "Domínio: https://$DOMINIO"
echo "Proxy configurado para porta: $PORTA"
