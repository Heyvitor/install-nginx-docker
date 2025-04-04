#!/bin/bash

# Verificar se é root
if [ "$(id -u)" -ne 0 ]; then
  echo "Execute este script como root ou com sudo"
  exit 1
fi

# Instalar figlet se não estiver presente
if ! command -v figlet &> /dev/null; then
  sudo apt install -y figlet
fi

# Definir cores
BLUE_BG="\033[44m"   # Fundo azul
WHITE_TEXT="\033[97m" # Texto branco
RESET="\033[0m"      # Resetar cores

# Obter largura do terminal
TERM_WIDTH=$(tput cols)

# Função para centralizar texto
center_text() {
  local text="$1"
  local width="$2"
  local text_length=${#text}
  local padding=$(( (width - text_length) / 2 ))
  printf "%*s%s%*s\n" $padding "" "$text" $padding ""
}

# Exibir cabeçalho com fundo azul
echo -e "${BLUE_BG}${WHITE_TEXT}"
echo ""
center_text "VR PRIME" $TERM_WIDTH
center_text "https://www.vrprime.com.br" $TERM_WIDTH
echo ""
echo -e "${RESET}"

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

# Pedir domínio e email
if [ "$APP_TYPE" == "3" ]; then
  read -p "Digite o domínio para o N8N (ex: n8n.meusite.com): " N8N_HOST
  DOMINIO=$N8N_HOST
  read -p "Digite a versão do N8N (ex: 1.56.0): " N8N_VERSION
  if [ -z "$N8N_VERSION" ]; then
    echo "Versão do N8N não pode ser vazia"
    exit 1
  fi
else
  read -p "Digite o domínio (ex: meusite.com): " DOMINIO
fi
read -p "Digite o email para SSL [opcional, padrão admin@$DOMINIO]: " EMAIL_INPUT
EMAIL=${EMAIL_INPUT:-admin@$DOMINIO}

# Diretório de configurações
CONFIG_DIR="/vrprime/configs"

# Verificar se o diretório de configurações existe
if [ ! -d "$CONFIG_DIR" ]; then
  echo "Diretório de configurações não encontrado: $CONFIG_DIR"
  exit 1
fi

# Configuração específica por tipo
if [ "$APP_TYPE" == "1" ]; then
  read -p "Digite o caminho completo para a pasta public do Laravel: " LARAVEL_PATH
  if [ ! -d "$LARAVEL_PATH" ]; then
    echo "Pasta não encontrada: $LARAVEL_PATH"
    exit 1
  fi
  # Verificar se o arquivo de configuração existe
  if [ ! -f "$CONFIG_DIR/laravel.conf" ]; then
    echo "Arquivo de configuração não encontrado: $CONFIG_DIR/laravel.conf"
    exit 1
  fi
  # Copiar e substituir placeholders
  sudo sed -e "s|\$DOMINIO|$DOMINIO|g" -e "s|\$LARAVEL_PATH|$LARAVEL_PATH|g" "$CONFIG_DIR/laravel.conf" > "/etc/nginx/sites-available/$DOMINIO"
elif [ "$APP_TYPE" == "2" ]; then
  read -p "Digite a porta do servidor Node.js: " PORTA
  if ! [[ "$PORTA" =~ ^[0-9]+$ ]]; then
    echo "Porta inválida"
    exit 1
  fi
  # Verificar se o arquivo de configuração existe
  if [ ! -f "$CONFIG_DIR/node.conf" ]; then
    echo "Arquivo de configuração não encontrado: $CONFIG_DIR/node.conf"
    exit 1
  fi
  # Copiar e substituir placeholders
  sudo sed -e "s|\$DOMINIO|$DOMINIO|g" -e "s|\$PORTA|$PORTA|g" "$CONFIG_DIR/node.conf" > "/etc/nginx/sites-available/$DOMINIO"
elif [ "$APP_TYPE" == "3" ]; then
  N8N_PORT=5678
  # Criar diretório para o N8N
  N8N_DIR="/opt/n8n"
  sudo mkdir -p "$N8N_DIR"
  cd "$N8N_DIR"
  
  # Verificar se o arquivo de configuração existe
  if [ ! -f "$CONFIG_DIR/n8n-composer.yaml" ]; then
    echo "Arquivo de configuração não encontrado: $CONFIG_DIR/n8n-composer.yaml"
    exit 1
  fi
  # Copiar e substituir placeholders
  sudo sed -e "s|\$N8N_HOST|$N8N_HOST|g" -e "s|\$N8N_VERSION|$N8N_VERSION|g" "$CONFIG_DIR/n8n-composer.yaml" > "$N8N_DIR/docker-compose.yml"
  # Iniciar o Docker Compose
  sudo docker-compose up -d

  # Verificar se o arquivo de configuração Nginx existe
  if [ ! -f "$CONFIG_DIR/n8n.conf" ]; then
    echo "Arquivo de configuração não encontrado: $CONFIG_DIR/n8n.conf"
    exit 1
  fi
  # Copiar e substituir placeholders
  sudo sed -e "s|\$DOMINIO|$DOMINIO|g" "$CONFIG_DIR/n8n.conf" > "/etc/nginx/sites-available/$DOMINIO"
fi

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
if [ "$APP_TYPE" == "1" ]; then
  echo "Laravel configurado na pasta: $LARAVEL_PATH"
elif [ "$APP_TYPE" == "2" ]; then
  echo "Proxy configurado para porta: $PORTA"
elif [ "$APP_TYPE" == "3" ]; then
  echo "N8N configurado via Docker no domínio: $DOMINIO com versão $N8N_VERSION"
fi