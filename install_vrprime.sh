#!/bin/bash

# Definir cores
BLUE_BG="\033[44m"
WHITE_TEXT="\033[97m"
RESET="\033[0m"

# Verificar se é root
if [ "$(id -u)" -ne 0 ]; then
  echo "Execute este script como root ou com sudo"
  exit 1
fi

# Função para centralizar texto
center_text() {
  local text="$1"
  local width="$2"
  local text_length=${#text}
  local padding=$(( (width - text_length) / 2 ))
  printf "%*s%s%*s\n" $padding "" "$text" $padding ""
}

# Exibir cabeçalho
TERM_WIDTH=$(tput cols)
printf "${BLUE_BG}${WHITE_TEXT}\n\n"
center_text "VR PRIME" $TERM_WIDTH
center_text "https://www.vrprime.com.br" $TERM_WIDTH
printf "\n${RESET}\n"

# Diretórios base
INSTALL_DIR="/home/install-nginx-docker/vrprime/install"
COMPOSER_DIR="/home/install-nginx-docker/vrprime/composer"
NGINX_DIR="/home/install-nginx-docker/vrprime/nginx"
REGISTRY_FILE="/home/install-nginx-docker/vrprime/installations.txt"

# Criar diretórios se não existirem
sudo mkdir -p "$INSTALL_DIR" "$COMPOSER_DIR" "$NGINX_DIR"
sudo touch "$REGISTRY_FILE" 2>/dev/null
sudo chmod 666 "$REGISTRY_FILE" 2>/dev/null

# Função para gerar uma chave ou senha
generate_key() {
  openssl rand -base64 48 | tr -d '/+=' | head -c 32
}

# Função para gerar SECRET_KEY_BASE (128 caracteres, base64)
generate_secret_key_base() {
  openssl rand -base64 96 | tr -d '/+=' | head -c 128
}

# Função para registrar uma instalação no arquivo de registro
register_installation() {
  local domain="$1"
  local app_type="$2"
  local composer_file="$3"
  local install_dir="$4"
  echo "$domain|$app_type|$composer_file|$install_dir" | sudo tee -a "$REGISTRY_FILE" > /dev/null
}

# Menu de seleção
echo "Selecione o tipo de operação:"
echo "1) Instalar aplicação"
echo "2) Desinstalar aplicação"
read -p "Opção (1/2): " OPERATION_TYPE

if [ "$OPERATION_TYPE" != "1" ] && [ "$OPERATION_TYPE" != "2" ]; then
  echo "Opção inválida"
  exit 1
fi

# Se a opção for desinstalar
if [ "$OPERATION_TYPE" = "2" ]; then
  # Verificar se existe o arquivo de registro
  if [ ! -f "$REGISTRY_FILE" ] || [ ! -s "$REGISTRY_FILE" ]; then
    echo "Nenhuma aplicação registrada para desinstalação."
    
    # Tentar detectar instalações não registradas
    echo "Verificando instalações não registradas..."
    
    # Verificar pastas no diretório de instalação
    if [ -d "$INSTALL_DIR" ] && [ "$(ls -A "$INSTALL_DIR" 2>/dev/null)" ]; then
      echo "Encontradas pastas no diretório de instalação:"
      for dir in "$INSTALL_DIR"/*; do
        if [ -d "$dir" ]; then
          echo "- $(basename "$dir")"
        fi
      done
      
      read -p "Digite o nome da pasta da aplicação a ser desinstalada: " SELECTED_DIR
      
      if [ -z "$SELECTED_DIR" ]; then
        echo "Nome de pasta inválido"
        exit 1
      fi
      
      APP_DIR="$INSTALL_DIR/$SELECTED_DIR"
      
      if [ ! -d "$APP_DIR" ]; then
        echo "Diretório não encontrado: $APP_DIR"
        exit 1
      fi
      
      # Confirmar a desinstalação
      read -p "Esta ação removerá a pasta $APP_DIR e possivelmente os volumes Docker associados. Continuar? (s/n): " CONFIRM
      if [ "$CONFIRM" != "s" ] && [ "$CONFIRM" != "S" ]; then
        echo "Operação cancelada."
        exit 0
      fi
      
      # Desinstalar a aplicação
      echo "Desinstalando a aplicação em $APP_DIR..."
      
      # Verificar se é uma aplicação Docker
      if [ -f "$APP_DIR/docker-compose.yml" ]; then
        cd "$APP_DIR"
        echo "Parando e removendo contêineres..."
        sudo docker-compose down -v
        
        # Tentar encontrar e remover volumes
        echo "Procurando volumes associados..."
        DIR_NAME=$(basename "$APP_DIR")
        VOLUME_PREFIX=$(echo "$DIR_NAME" | tr '-' '_')
        
        for VOLUME in $(sudo docker volume ls -q | grep "$VOLUME_PREFIX" 2>/dev/null); do
          echo "Removendo volume: $VOLUME"
          sudo docker volume rm "$VOLUME" || true
        done
      fi
      
      # Tentar encontrar e remover configuração Nginx
      echo "Procurando configurações Nginx relacionadas..."
      for NGINX_CONF in $(ls /etc/nginx/sites-available/ 2>/dev/null); do
        # Verificar se o arquivo contém o nome do diretório
        if grep -q "$SELECTED_DIR" "/etc/nginx/sites-available/$NGINX_CONF" 2>/dev/null; then
          echo "Removendo configuração Nginx: $NGINX_CONF"
          sudo rm -f "/etc/nginx/sites-enabled/$NGINX_CONF" 2>/dev/null
          sudo rm -f "/etc/nginx/sites-available/$NGINX_CONF" 2>/dev/null
        fi
      done
      
      # Remover o diretório
      sudo rm -rf "$APP_DIR"
      echo "Diretório de instalação removido."
      
      # Recarregar Nginx
      sudo systemctl reload nginx
      
      echo "Desinstalação concluída."
      exit 0
    else
      echo "Nenhuma aplicação encontrada para desinstalar."
      exit 1
    fi
  fi
  
  # Listar instalações registradas
  echo "Aplicações instaladas:"
  i=1
  while read -r LINE; do
    DOMAIN=$(echo "$LINE" | cut -d'|' -f1)
    APP_TYPE=$(echo "$LINE" | cut -d'|' -f2)
    INSTALL_PATH=$(echo "$LINE" | cut -d'|' -f4)
    echo "$i) $APP_TYPE - Domínio: $DOMAIN - Diretório: $INSTALL_PATH"
    i=$((i+1))
  done < "$REGISTRY_FILE"
  
  # Pedir ao usuário para selecionar uma aplicação
  read -p "Digite o número da aplicação a ser desinstalada: " APP_NUMBER
  
  # Validar a entrada
  if ! echo "$APP_NUMBER" | grep -q "^[0-9]\+$"; then
    echo "Número inválido"
    exit 1
  fi
  
  # Obter a linha correspondente ao número selecionado
  SELECTED_LINE=$(sed -n "${APP_NUMBER}p" "$REGISTRY_FILE")
  
  if [ -z "$SELECTED_LINE" ]; then
    echo "Aplicação não encontrada"
    exit 1
  fi
  
  # Extrair informações da linha selecionada
  DOMAIN=$(echo "$SELECTED_LINE" | cut -d'|' -f1)
  APP_TYPE=$(echo "$SELECTED_LINE" | cut -d'|' -f2)
  COMPOSER_FILE=$(echo "$SELECTED_LINE" | cut -d'|' -f3)
  INSTALL_PATH=$(echo "$SELECTED_LINE" | cut -d'|' -f4)
  
  # Confirmar a desinstalação
  echo "Você selecionou: $APP_TYPE - $DOMAIN - $INSTALL_PATH"
  read -p "Esta ação removerá todos os dados da aplicação. Continuar? (s/n): " CONFIRM
  if [ "$CONFIRM" != "s" ] && [ "$CONFIRM" != "S" ]; then
    echo "Operação cancelada."
    exit 0
  fi
  
  echo "Desinstalando $APP_TYPE - $DOMAIN..."
  
  # Verificar se o diretório de instalação existe
  if [ -d "$INSTALL_PATH" ]; then
    # Para aplicações Docker
    if [ -f "$INSTALL_PATH/docker-compose.yml" ]; then
      # Parar e remover os contêineres
      cd "$INSTALL_PATH"
      echo "Parando e removendo contêineres..."
      sudo docker-compose down -v
      
      # Identificar e remover volumes Docker
      echo "Removendo volumes Docker associados..."
      
      # Extrair nome da base do diretório
      DIR_NAME=$(basename "$INSTALL_PATH")
      VOLUME_PREFIX=$(echo "$DIR_NAME" | tr '-' '_')
      
      # Procurar volumes com o prefixo correspondente
      for VOLUME in $(sudo docker volume ls -q | grep "$VOLUME_PREFIX" 2>/dev/null); do
        echo "Removendo volume: $VOLUME"
        sudo docker volume rm "$VOLUME" || true
      done
      
      # Remover diretório da aplicação
      sudo rm -rf "$INSTALL_PATH"
      echo "Diretório de instalação removido: $INSTALL_PATH"
    else
      echo "Arquivo docker-compose.yml não encontrado em $INSTALL_PATH"
      sudo rm -rf "$INSTALL_PATH"
      echo "Diretório de instalação removido: $INSTALL_PATH"
    fi
  else
    echo "Diretório de instalação não encontrado: $INSTALL_PATH"
  fi
  
  # Verificar configuração Nginx
  NGINX_CONF="/etc/nginx/sites-available/$DOMAIN"
  if [ -f "$NGINX_CONF" ]; then
    echo "Removendo configuração Nginx para $DOMAIN..."
    sudo rm -f "/etc/nginx/sites-enabled/$DOMAIN" 2>/dev/null
    sudo rm -f "$NGINX_CONF"
    sudo systemctl reload nginx
    echo "Configuração Nginx removida."
  else
    echo "Configuração Nginx não encontrada para $DOMAIN."
  fi
  
  # Remover entrada do arquivo de registro
  echo "Removendo entrada do registro de instalações..."
  grep -v "^$DOMAIN|" "$REGISTRY_FILE" | sudo tee "$REGISTRY_FILE.tmp" > /dev/null
  sudo mv "$REGISTRY_FILE.tmp" "$REGISTRY_FILE"
  
  echo "Desinstalação de $APP_TYPE - $DOMAIN concluída com sucesso!"
  exit 0
fi

# Menu de seleção para instalação
echo "Selecione o tipo de aplicação:"
echo "1) Laravel"
echo "2) Node.js/Express"
echo "3) N8N - Docker"
echo "4) EVOLUTION API - Docker"
echo "5) PG Admin - Docker"
echo "6) WordPress - Docker"
echo "7) MySql+PhpMyAdmin - Docker"
echo "8) Chatwoot - Docker"
read -p "Opção (1/2/3/4/5/6/7/8): " APP_TYPE

if [ "$APP_TYPE" != "1" ] && [ "$APP_TYPE" != "2" ] && [ "$APP_TYPE" != "3" ] && \
   [ "$APP_TYPE" != "4" ] && [ "$APP_TYPE" != "5" ] && [ "$APP_TYPE" != "6" ] && \
   [ "$APP_TYPE" != "7" ] && [ "$APP_TYPE" != "8" ]; then
  echo "Opção inválida"
  exit 1
fi

# Pedir domínio e email
case "$APP_TYPE" in
  3)
    read -p "Digite o domínio para o N8N (ex: n8n.meusite.com): " N8N_HOST
    DOMINIO=$N8N_HOST
    read -p "Digite a versão do N8N (ex: 1.56.0): " N8N_VERSION
    if [ -z "$N8N_VERSION" ]; then
      echo "Versão do N8N não pode ser vazia"
      exit 1
    fi
    APP_DIR="$INSTALL_DIR/n8n"
    ;;
  4)
    read -p "Digite o domínio para o Evolution API (ex: evolution.meusite.com): " SERVER_URL
    DOMINIO=$SERVER_URL
    read -p "Digite a versão do Evolution API (ex: v2.2.3) [padrão: v2.2.3]: " EVOLUTION_VERSION
    EVOLUTION_VERSION=${EVOLUTION_VERSION:-v2.2.3}
    read -p "Digite a porta externa para o Evolution API (ex: 8080): " EVOLUTION_PORT
    case "$EVOLUTION_PORT" in
      ''|*[!0-9]*) echo "Porta inválida"; exit 1 ;;
    esac
    read -p "Digite a senha do PostgreSQL (ou deixe em branco para gerar automaticamente): " POSTGRES_PASSWORD
    if [ -z "$POSTGRES_PASSWORD" ]; then
      POSTGRES_PASSWORD=$(generate_key)
    fi
    AUTHENTICATION_API_KEY=$(generate_secret_key_base)
    APP_DIR="$INSTALL_DIR/evolution"
    ;;
  5)
    read -p "Digite o domínio para o PG Admin (ex: pgadmin.meusite.com): " DOMINIO
    read -p "Digite a porta externa para o PG Admin (ex: 5050): " PGADMIN_PORT
    read -p "Digite a porta externa para o PostgreSQL (ex: 5432): " POSTGRES_PORT
    read -p "Digite o email para o PG Admin: " PGADMIN_DEFAULT_EMAIL
    read -p "Digite a senha para o PG Admin: " PGADMIN_DEFAULT_PASSWORD
    read -p "Digite a senha para o PostgreSQL (ou deixe em branco para gerar automaticamente): " POSTGRES_PASSWORD
    if [ -z "$POSTGRES_PASSWORD" ]; then
      POSTGRES_PASSWORD=$(generate_key)
    fi
    POSTGRES_DB="pgadmin_db_$(openssl rand -hex 4)"
    APP_DIR="$INSTALL_DIR/pgadmin"
    ;;
  6)
    read -p "Digite o domínio para o WordPress (ex: wordpress.meusite.com): " DOMINIO
    read -p "Digite a porta externa para o WordPress (ex: 8080): " WORDPRESS_PORT
    MYSQL_DATABASE="wordpress_db_$(openssl rand -hex 4)"
    MYSQL_USER="wp_user_$(openssl rand -hex 4)"
    MYSQL_PASSWORD=$(generate_key)
    MYSQL_ROOT_PASSWORD=$(generate_key)
    APP_DIR="$INSTALL_DIR/wordpress"
    ;;
  7)
    read -p "Digite o domínio para o PhpMyAdmin (ex: phpmyadmin.meusite.com): " DOMINIO
    read -p "Digite a porta externa para o PhpMyAdmin (ex: 8081): " PHPMYADMIN_PORT
    read -p "Digite o usuário para o MySQL: " MYSQL_USER
    read -p "Digite a senha para o MySQL: " MYSQL_PASSWORD
    MYSQL_ROOT_PASSWORD=$(generate_key)
    MYSQL_DATABASE="mysql"
    APP_DIR="$INSTALL_DIR/mysql-phpmyadmin"
    ;;
  8)
    read -p "Digite o domínio para o Chatwoot (ex: chatwoot.meusite.com): " DOMINIO
    read -p "Digite a porta externa para o Chatwoot (ex: 3000): " CHATWOOT_PORT
    read -p "Digite a senha do PostgreSQL (ou deixe em branco para gerar automaticamente): " POSTGRES_PASSWORD
    if [ -z "$POSTGRES_PASSWORD" ]; then
      POSTGRES_PASSWORD=$(openssl rand -base64 12 | tr -d '\n' | head -c 16)
    fi
    SECRET_KEY_BASE=$(generate_secret_key_base)
    POSTGRES_DATABASE="chatwoot_db_$(openssl rand -hex 4)"
    POSTGRES_USERNAME="chatwoot_user_$(openssl rand -hex 4)"
    APP_DIR="$INSTALL_DIR/chatwoot"
    ;;
  *)
    read -p "Digite o domínio (ex: meusite.com): " DOMINIO
    APP_DIR="$INSTALL_DIR/$DOMINIO"
    ;;
esac

read -p "Digite o email para SSL [opcional, padrão admin@$DOMINIO]: " EMAIL_INPUT
EMAIL=${EMAIL_INPUT:-admin@$DOMINIO}

# Configuração específica por tipo
case "$APP_TYPE" in
  1)
    read -p "Digite o caminho completo para a pasta public do Laravel: " LARAVEL_PATH
    if [ ! -d "$LARAVEL_PATH" ]; then
      echo "Pasta não encontrada: $LARAVEL_PATH"
      exit 1
    fi
    if [ ! -f "$NGINX_DIR/laravel.conf" ]; then
      echo "Arquivo de configuração não encontrado: $NGINX_DIR/laravel.conf"
      exit 1
    fi
    sudo sed -e "s|\$DOMINIO|$DOMINIO|g" -e "s|\$LARAVEL_PATH|$LARAVEL_PATH|g" "$NGINX_DIR/laravel.conf" > "/etc/nginx/sites-available/$DOMINIO"
    # Adicionar registro de instalação
    register_installation "$DOMINIO" "Laravel" "N/A" "$LARAVEL_PATH"
    ;;
  2)
    read -p "Digite a porta do servidor Node.js: " PORTA
    case "$PORTA" in
      ''|*[!0-9]*) echo "Porta inválida"; exit 1 ;;
    esac
    if [ ! -f "$NGINX_DIR/node.conf" ]; then
      echo "Arquivo de configuração não encontrado: $NGINX_DIR/node.conf"
      exit 1
    fi
    sudo sed -e "s|\$DOMINIO|$DOMINIO|g" -e "s|\$PORTA|$PORTA|g" "$NGINX_DIR/node.conf" > "/etc/nginx/sites-available/$DOMINIO"
    # Adicionar registro de instalação
    register_installation "$DOMINIO" "Node.js" "N/A" "$INSTALL_DIR/$DOMINIO"
    ;;
  3)
    sudo mkdir -p "$APP_DIR"
    cd "$APP_DIR"
    if [ ! -f "$COMPOSER_DIR/n8n-composer.yaml" ]; then
      echo "Arquivo de configuração não encontrado: $COMPOSER_DIR/n8n-composer.yaml"
      exit 1
    fi
    sudo sed -e "s|\$N8N_VERSION|$N8N_VERSION|g" "$COMPOSER_DIR/n8n-composer.yaml" > "$APP_DIR/docker-compose.yml"
    sudo tee "$APP_DIR/.env" > /dev/null << EOL
N8N_HOST=$N8N_HOST
N8N_PORT=5678
N8N_PROTOCOL=https
NODE_ENV=production
WEBHOOK_URL=https://$N8N_HOST/
GENERIC_TIMEZONE=America/Sao_Paulo
N8N_SECURE_COOKIE=false
N8N_RUNNERS_ENABLED=true
N8N_ENFORCE_SETTINGS_FILE_PERMISSIONS=true
EOL
    sudo docker-compose up -d
    if [ ! -f "$NGINX_DIR/n8n.conf" ]; then
      echo "Arquivo de configuração não encontrado: $NGINX_DIR/n8n.conf"
      exit 1
    fi
    sudo sed -e "s|\$DOMINIO|$DOMINIO|g" "$NGINX_DIR/n8n.conf" > "/etc/nginx/sites-available/$DOMINIO"
    # Adicionar registro de instalação
    register_installation "$DOMINIO" "N8N Docker" "n8n-composer.yaml" "$APP_DIR"
    ;;
  4)
    sudo mkdir -p "$APP_DIR"
    cd "$APP_DIR"
    if [ ! -f "$COMPOSER_DIR/evolution-composer.yaml" ]; then
      echo "Arquivo de configuração não encontrado: $COMPOSER_DIR/evolution-composer.yaml"
      exit 1
    fi
    sudo sed -e "s|\$EVOLUTION_VERSION|$EVOLUTION_VERSION|g" -e "s|\$EVOLUTION_PORT|$EVOLUTION_PORT|g" "$COMPOSER_DIR/evolution-composer.yaml" > "$APP_DIR/docker-compose.yml"
    sudo tee "$APP_DIR/.env" > /dev/null << EOL
SERVER_URL=https://$SERVER_URL
AUTHENTICATION_TYPE=apikey
AUTHENTICATION_API_KEY=$AUTHENTICATION_API_KEY
AUTHENTICATION_EXPOSE_IN_FETCH_INSTANCES=true
LANGUAGE=en
CONFIG_SESSION_PHONE_CLIENT=Windows
CONFIG_SESSION_PHONE_NAME=Firefox
TELEMETRY=false
TELEMETRY_URL=
DATABASE_ENABLED=true
DATABASE_PROVIDER=postgresql
DATABASE_CONNECTION_URI=postgres://postgresql:$POSTGRES_PASSWORD@evolution-postgres:5432/evolution
DATABASE_SAVE_DATA_INSTANCE=true
DATABASE_SAVE_DATA_NEW_MESSAGE=true
DATABASE_SAVE_MESSAGE_UPDATE=true
DATABASE_SAVE_DATA_CONTACTS=true
DATABASE_SAVE_DATA_CHATS=true
DATABASE_SAVE_DATA_LABELS=true
DATABASE_SAVE_DATA_HISTORIC=true
CACHE_REDIS_ENABLED=true
CACHE_REDIS_URI=redis://evolution-redis:6379
CACHE_REDIS_PREFIX_KEY=evolution
CACHE_REDIS_SAVE_INSTANCES=true
CHATWOOT_ENABLED=true
CHATWOOT_MESSAGE_READ=true
CHATWOOT_MESSAGE_DELETE=true
CHATWOOT_IMPORT_DATABASE_CONNECTION_URI=postgres://postgresql:$POSTGRES_PASSWORD@evolution-postgres:5432/evolution
POSTGRES_DB=evolution
POSTGRES_USER=postgresql
POSTGRES_PASSWORD=$POSTGRES_PASSWORD
EOL
    sudo docker-compose up -d
    if [ ! -f "$NGINX_DIR/evolution.conf" ]; then
      echo "Arquivo de configuração não encontrado: $NGINX_DIR/evolution.conf"
      exit 1
    fi
    sudo sed -e "s|\$DOMINIO|$DOMINIO|g" -e "s|localhost:8080|localhost:$EVOLUTION_PORT|g" "$NGINX_DIR/evolution.conf" > "/etc/nginx/sites-available/$DOMINIO"
    # Adicionar registro de instalação
    register_installation "$DOMINIO" "Evolution API Docker" "evolution-composer.yaml" "$APP_DIR"
    ;;
  5)
    sudo mkdir -p "$APP_DIR"
    cd "$APP_DIR"
    if [ ! -f "$COMPOSER_DIR/pgadmin-docker.yaml" ]; then
      echo "Arquivo de configuração não encontrado: $COMPOSER_DIR/pgadmin-docker.yaml"
      exit 1
    fi
    sudo cp "$COMPOSER_DIR/pgadmin-docker.yaml" "$APP_DIR/docker-compose.yml"
    sudo tee "$APP_DIR/.env" > /dev/null << EOL
PGADMIN_DEFAULT_EMAIL=$PGADMIN_DEFAULT_EMAIL
PGADMIN_DEFAULT_PASSWORD=$PGADMIN_DEFAULT_PASSWORD
POSTGRES_PASSWORD=$POSTGRES_PASSWORD
POSTGRES_DB=$POSTGRES_DB
POSTGRES_PORT=$POSTGRES_PORT
PGADMIN_PORT=$PGADMIN_PORT
EOL
    sudo docker-compose up -d
    if [ ! -f "$NGINX_DIR/pgadmin.conf" ]; then
      echo "Arquivo de configuração não encontrado: $NGINX_DIR/pgadmin.conf"
      exit 1
    fi
    sudo sed -e "s|\$DOMINIO|$DOMINIO|g" -e "s|\$PGADMIN_PORT|$PGADMIN_PORT|g" "$NGINX_DIR/pgadmin.conf" > "/etc/nginx/sites-available/$DOMINIO"
    # Adicionar registro de instalação
    register_installation "$DOMINIO" "PG Admin Docker" "pgadmin-docker.yaml" "$APP_DIR"
    ;;
  6)
    sudo mkdir -p "$APP_DIR"
    cd "$APP_DIR"
    if [ ! -f "$COMPOSER_DIR/wordpress-docker.yaml" ]; then
      echo "Arquivo de configuração não encontrado: $COMPOSER_DIR/wordpress-docker.yaml"
      exit 1
    fi
    sudo cp "$COMPOSER_DIR/wordpress-docker.yaml" "$APP_DIR/docker-compose.yml"
    sudo sed -i "s|\$WORDPRESS_PORT|$WORDPRESS_PORT|g" "$APP_DIR/docker-compose.yml"
    sudo tee "$APP_DIR/.env" > /dev/null << EOL
WORDPRESS_DB_HOST=db
WORDPRESS_DB_USER=$MYSQL_USER
WORDPRESS_DB_PASSWORD=$MYSQL_PASSWORD
WORDPRESS_DB_NAME=$MYSQL_DATABASE
MYSQL_DATABASE=$MYSQL_DATABASE
MYSQL_USER=$MYSQL_USER
MYSQL_PASSWORD=$MYSQL_PASSWORD
MYSQL_ROOT_PASSWORD=$MYSQL_ROOT_PASSWORD
EOL
    sudo docker-compose up -d
    if [ ! -f "$NGINX_DIR/wordpress.conf" ]; then
      echo "Arquivo de configuração não encontrado: $NGINX_DIR/wordpress.conf"
      exit 1
    fi
    sudo sed -e "s|\$DOMINIO|$DOMINIO|g" -e "s|\$WORDPRESS_PORT|$WORDPRESS_PORT|g" "$NGINX_DIR/wordpress.conf" > "/etc/nginx/sites-available/$DOMINIO"
    # Adicionar registro de instalação
    register_installation "$DOMINIO" "WordPress Docker" "wordpress-docker.yaml" "$APP_DIR"
    ;;
  7)
    sudo mkdir -p "$APP_DIR"
    cd "$APP_DIR"
    if [ ! -f "$COMPOSER_DIR/mysql-phpmy-composer.yaml" ]; then
      echo "Arquivo de configuração não encontrado: $COMPOSER_DIR/mysql-phpmy-composer.yaml"
      exit 1
    fi
    sudo cp "$COMPOSER_DIR/mysql-phpmy-composer.yaml" "$APP_DIR/docker-compose.yml"
    sudo sed -i "s|\$PHPMYADMIN_PORT|$PHPMYADMIN_PORT|g" "$APP_DIR/docker-compose.yml"
    sudo tee "$APP_DIR/.env" > /dev/null << EOL
MYSQL_ROOT_PASSWORD=$MYSQL_ROOT_PASSWORD
MYSQL_DATABASE=$MYSQL_DATABASE
MYSQL_USER=$MYSQL_USER
MYSQL_PASSWORD=$MYSQL_PASSWORD
PMA_HOST=db
PMA_ARBITRARY=0
PHPMYADMIN_PORT=$PHPMYADMIN_PORT
EOL
    sudo docker-compose up -d
    if [ ! -f "$NGINX_DIR/mysql-phpmy.conf" ]; then
      echo "Arquivo de configuração não encontrado: $NGINX_DIR/mysql-phpmy.conf"
      exit 1
    fi
    sudo sed -e "s|\$DOMINIO|$DOMINIO|g" -e "s|\$PHPMYADMIN_PORT|$PHPMYADMIN_PORT|g" "$NGINX_DIR/mysql-phpmy.conf" > "/etc/nginx/sites-available/$DOMINIO"
    # Adicionar registro de instalação
    register_installation "$DOMINIO" "MySQL+PhpMyAdmin Docker" "mysql-phpmy-composer.yaml" "$APP_DIR"
    ;;
  8)
    sudo mkdir -p "$APP_DIR"
    cd "$APP_DIR"
    if [ ! -f "$COMPOSER_DIR/chatwoot-composer.yaml" ]; then
      echo "Arquivo de configuração não encontrado: $COMPOSER_DIR/chatwoot-composer.yaml"
      exit 1
    fi
    
    # Verificar se todas as variáveis necessárias estão definidas
    if [ -z "$DOMINIO" ] || [ -z "$SECRET_KEY_BASE" ] || [ -z "$POSTGRES_DATABASE" ] || [ -z "$POSTGRES_USERNAME" ] || [ -z "$POSTGRES_PASSWORD" ] || [ -z "$CHATWOOT_PORT" ]; then
      echo "Erro: Uma ou mais variáveis necessárias não estão definidas"
      exit 1
    fi
    
    # Fazer as substituições com cada variável individualmente para melhor diagnóstico
    cp "$COMPOSER_DIR/chatwoot-composer.yaml" "$APP_DIR/docker-compose.yml"
    sed -i "s|\\\$DOMINIO|$DOMINIO|g" "$APP_DIR/docker-compose.yml"
    sed -i "s|\\\$SECRET_KEY_BASE|$SECRET_KEY_BASE|g" "$APP_DIR/docker-compose.yml"
    sed -i "s|\\\$POSTGRES_DATABASE|$POSTGRES_DATABASE|g" "$APP_DIR/docker-compose.yml"
    sed -i "s|\\\$POSTGRES_USERNAME|$POSTGRES_USERNAME|g" "$APP_DIR/docker-compose.yml"
    sed -i "s|\\\$POSTGRES_PASSWORD|$POSTGRES_PASSWORD|g" "$APP_DIR/docker-compose.yml"
    sed -i "s|\\\$CHATWOOT_PORT|$CHATWOOT_PORT|g" "$APP_DIR/docker-compose.yml"
    
    sudo tee "$APP_DIR/.env" > /dev/null << EOL
FRONTEND_URL=https://$DOMINIO
SECRET_KEY_BASE=$SECRET_KEY_BASE
RAILS_ENV=production
NODE_ENV=production
INSTALLATION_ENV=docker
RAILS_LOG_TO_STDOUT=true
LOG_LEVEL=info
DEFAULT_LOCALE=en
POSTGRES_HOST=chatwoot-postgres
POSTGRES_PORT=5432
POSTGRES_DATABASE=$POSTGRES_DATABASE
POSTGRES_USERNAME=$POSTGRES_USERNAME
POSTGRES_PASSWORD=$POSTGRES_PASSWORD
REDIS_URL=redis://chatwoot-redis:6379
ENABLE_ACCOUNT_SIGNUP=false
ACTIVE_STORAGE_SERVICE=local
EOL
    sudo docker-compose up -d
    if [ ! -f "$NGINX_DIR/chatwoot.conf" ]; then
      echo "Arquivo de configuração não encontrado: $NGINX_DIR/chatwoot.conf"
      exit 1
    fi
    sudo sed -e "s|\$DOMINIO|$DOMINIO|g" -e "s|\$CHATWOOT_PORT|$CHATWOOT_PORT|g" "$NGINX_DIR/chatwoot.conf" > "/etc/nginx/sites-available/$DOMINIO"
    # Adicionar registro de instalação
    register_installation "$DOMINIO" "Chatwoot Docker" "chatwoot-composer.yaml" "$APP_DIR"
    ;;
esac

# Instalar Certbot se não existir
if ! command -v certbot &> /dev/null; then
  echo "Instalando Certbot para SSL..."
  sudo apt install -y certbot python3-certbot-nginx
fi

# Habilitar site
sudo ln -sf "/etc/nginx/sites-available/$DOMINIO" "/etc/nginx/sites-enabled/"
sudo nginx -t && sudo systemctl reload nginx

# Configurar SSL
echo "Obtendo certificado SSL para $DOMINIO..."
sudo certbot --nginx -d "$DOMINIO" --non-interactive --agree-tos -m "$EMAIL"

# Configurar renovação automática
if [ $? -eq 0 ]; then
  (crontab -l 2>/dev/null; echo "0 12 * * * /usr/bin/certbot renew --quiet") | crontab -
fi

echo "Configuração concluída!"
echo "Domínio: https://$DOMINIO"
case "$APP_TYPE" in
  1)
    echo "Laravel configurado na pasta: $LARAVEL_PATH"
    ;;
  2)
    echo "Proxy configurado para porta: $PORTA"
    ;;
  3)
    echo "N8N configurado via Docker no domínio: $DOMINIO com versão $N8N_VERSION"
    ;;
  4)
    echo "Evolution API configurado via Docker no domínio: $DOMINIO com versão $EVOLUTION_VERSION"
    echo "Porta externa: $EVOLUTION_PORT"
    echo "Chave de autenticação gerada: $AUTHENTICATION_API_KEY"
    echo "Senha PostgreSQL: $POSTGRES_PASSWORD"
    ;;
  5)
    echo "PG Admin configurado via Docker no domínio: $DOMINIO com porta $PGADMIN_PORT"
    echo "Porta PostgreSQL: $POSTGRES_PORT"
    echo "Banco de dados: $POSTGRES_DB"
    echo "Email PG Admin: $PGADMIN_DEFAULT_EMAIL"
    echo "Senha PG Admin: $PGADMIN_DEFAULT_PASSWORD"
    echo "Senha PostgreSQL: $POSTGRES_PASSWORD"
    ;;
  6)
    echo "WordPress configurado via Docker no domínio: $DOMINIO com porta $WORDPRESS_PORT"
    echo "Banco de dados: $MYSQL_DATABASE"
    echo "Usuário: $MYSQL_USER"
    echo "Senha: $MYSQL_PASSWORD"
    echo "Senha root: $MYSQL_ROOT_PASSWORD"
    ;;
  7)
    echo "MySql+PhpMyAdmin configurado via Docker no domínio: $DOMINIO com porta $PHPMYADMIN_PORT"
    echo "Usuário MySQL: $MYSQL_USER"
    echo "Senha MySQL: $MYSQL_PASSWORD"
    echo "Senha root MySQL: $MYSQL_ROOT_PASSWORD"
    ;;
  8)
    echo "Chatwoot configurado via Docker no domínio: $DOMINIO com porta $CHATWOOT_PORT"
    echo "Banco de dados: $POSTGRES_DATABASE"
    echo "Usuário PostgreSQL: $POSTGRES_USERNAME"
    echo "Senha PostgreSQL: $POSTGRES_PASSWORD"
    echo "Secret Key Base: $SECRET_KEY_BASE"
    ;;
esac