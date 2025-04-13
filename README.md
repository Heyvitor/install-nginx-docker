# VR Prime Installation Script

## Descrição

O `install_vrprime.sh` é um script Bash projetado para automatizar a instalação e configuração de várias aplicações web em um servidor Linux usando Docker e Nginx como proxy reverso. Ele suporta a implantação de diferentes tipos de aplicações, incluindo Laravel, Node.js/Express, e várias soluções baseadas em Docker, como N8N, Evolution API, PG Admin, WordPress, MySQL+PhpMyAdmin e Chatwoot. O script configura automaticamente o Nginx, obtém certificados SSL via Certbot e gerencia variáveis de ambiente para cada aplicação.

O projeto é mantido pela **VR Prime** ([vrprime.com.br](https://www.vrprime.com.br)) e foi desenvolvido para simplificar a implantação de aplicações em servidores.

## Funcionalidades

O script oferece suporte para as seguintes aplicações:

1. **Laravel**: Configura um projeto Laravel com Nginx apontando para a pasta `public`.
2. **Node.js/Express**: Configura um servidor Node.js com proxy reverso para uma porta específica.
3. **N8N - Docker**: Implanta o N8N (ferramenta de automação de fluxos) com uma versão específica.
4. **Evolution API - Docker**: Configura a API Evolution com PostgreSQL e Redis.
5. **PG Admin - Docker**: Implanta o PG Admin para gerenciamento de bancos PostgreSQL.
6. **WordPress - Docker**: Configura o WordPress com MySQL.
7. **MySQL+PhpMyAdmin - Docker**: Implanta MySQL com PhpMyAdmin para gerenciamento de bancos.
8. **Chatwoot - Docker**: Configura o Chatwoot (plataforma de atendimento ao cliente) com PostgreSQL e Redis.

### Recursos Adicionais
- **SSL Automático**: Usa Certbot para obter e renovar certificados SSL para todos os domínios configurados.
- **Configuração de Nginx**: Gera automaticamente arquivos de configuração do Nginx para proxy reverso.
- **Geração de Chaves**: Cria senhas e chaves seguras (ex.: `SECRET_KEY_BASE`, senhas de banco) automaticamente.
- **Docker Compose**: Gerencia serviços Docker com arquivos `docker-compose.yml` personalizados.
- **Ambiente Seguro**: Executa verificações de root e valida entradas do usuário.

## Pré-requisitos

Antes de executar o script, certifique-se de que o servidor atende aos seguintes requisitos:

- **Sistema Operacional**: Linux (recomendado Ubuntu 20.04 ou superior).
- **Usuário Root ou Sudo**: O script deve ser executado com privilégios de administrador.
- **Docker**: Instalado e configurado.
  ```bash
  sudo apt update
  sudo apt install -y docker.io
  sudo systemctl enable docker
  sudo systemctl start docker
  ```
- **Docker Compose**: Instalado (versão 1.25.0 ou superior).
  ```bash
  sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
  sudo chmod +x /usr/local/bin/docker-compose
  ```
- **Ferramentas Básicas**: `openssl`, `tput`, `sed`, e outras utilidades padrão do Linux.
  ```bash
  sudo apt install -y openssl
  ```
- **Conexão à Internet**: Necessária para baixar imagens Docker e certificados SSL.
- **Domínio Configurado**: Um domínio apontando para o IP do servidor (necessário para SSL).

## Estrutura do Projeto

O projeto utiliza os seguintes diretórios e arquivos:

- **`install_vrprime.sh`**: Script principal que gerencia a instalação e configuração.
- **`/home/install-nginx-docker/vrprime/composer/`**: Contém arquivos `docker-compose.yaml` para cada aplicação Docker:
  - `n8n-composer.yaml`
  - `evolution-composer.yaml`
  - `pgadmin-docker.yaml`
  - `wordpress-docker.yaml`
  - `mysql-phpmy-composer.yaml`
  - `chatwoot-composer.yaml`
- **`/home/install-nginx-docker/vrprime/nginx/`**: Contém configurações do Nginx:
  - `laravel.conf`
  - `node.conf`
  - `n8n.conf`
  - `evolution.conf`
  - `pgadmin.conf`
  - `wordpress.conf`
  - `mysql-phpmy.conf`
  - `chatwoot.conf`
- **`/home/install-nginx-docker/vrprime/install/`**: Diretório onde os arquivos de configuração de cada aplicação são gerados durante a instalação.

## Como Usar

1. **Clone o Repositório ou Baixe o Script**:
   - Se o projeto estiver em um repositório Git:
     ```bash
     git clone <URL_DO_REPOSITORIO>
     cd <NOME_DO_REPOSITORIO>
     ```
   - Ou copie o `install_vrprime.sh` e os diretórios `composer` e `nginx` para o servidor.

2. **Dê Permissões ao Script**:
   ```bash
   chmod +x install_vrprime.sh
   ```

3. **Execute o Script**:
   - Rode com privilégios de administrador:
     ```bash
     sudo ./install_vrprime.sh
     ```

4. **Siga as Instruções**:
   - Escolha uma opção do menu (1 a 8) correspondente à aplicação desejada.
   - Forneça as informações solicitadas, como:
     - Domínio (ex.: `meusite.com` ou `subdominio.meusite.com`).
     - Porta externa (quando aplicável).
     - Credenciais (ex.: email e senha para PG Admin, senha do banco para Chatwoot).
     - Algumas senhas e chaves são geradas automaticamente se não fornecidas.
   - O script configurará a aplicação, o Nginx, e o SSL automaticamente.

5. **Verifique a Saída**:
   - Ao final, o script exibe informações como o domínio configurado, porta, credenciais geradas, e outros detalhes relevantes.
   - Exemplo para Chatwoot:
     ```
     Configuração concluída!
     Domínio: https://chatwoot.meusite.com
     Chatwoot configurado via Docker no domínio: chatwoot.meusite.com com porta 3000
     Banco de dados: chatwoot_db_a1b2
     Usuário PostgreSQL: chatwoot_user_c3d4
     Senha PostgreSQL: k7m9p2q8w3e5r6t
     Secret Key Base: OGRzsKDn0XVma7Atf8HbnSEmzsn1O1Rf...
     ```

6. **Acesse a Aplicação**:
   - Use o domínio configurado (ex.: `https://chatwoot.meusite.com`) para acessar a aplicação no navegador.
   - Para aplicações Docker, verifique os logs se necessário:
     ```bash
     sudo docker-compose -f /home/install-nginx-docker/vrprime/install/<nome_app>/docker-compose.yml logs
     ```

## Exemplos de Configuração

### Instalando o Chatwoot
1. Escolha a opção 8 no menu.
2. Insira o domínio (ex.: `chatwoot.meusite.com`).
3. Insira a porta externa (ex.: `3000`).
4. Forneça a senha do PostgreSQL ou deixe em branco para gerar automaticamente.
5. Insira o email para SSL (ex.: `admin@meusite.com`).
6. O script configura o Chatwoot com PostgreSQL, Redis, Nginx, e SSL.

### Instalando o WordPress
1. Escolha a opção 6 no menu.
2. Insira o domínio (ex.: `wordpress.meusite.com`).
3. Insira a porta externa (ex.: `8080`).
4. O script gera automaticamente credenciais para o MySQL e configura o WordPress.

## Solução de Problemas

- **Erro de Permissão**: Certifique-se de executar o script com `sudo`.
- **Docker Não Iniciado**: Verifique se o Docker está rodando:
  ```bash
  sudo systemctl status docker
  ```
- **Falha no SSL**: Confirme que o domínio está apontando para o IP do servidor e que as portas 80 e 443 estão abertas.
- **Erro de Banco de Dados**: Para aplicações Docker, verifique os logs:
  ```bash
  sudo docker logs <container_id>
  ```
- **Arquivos Ausentes**: Certifique-se de que os arquivos em `composer/` e `nginx/` estão presentes e com permissões corretas (`chmod 644`).

## Contribuição

Contribuições são bem-vindas! Para sugerir melhorias ou reportar bugs:
1. Fork o repositório.
2. Crie uma branch para sua feature (`git checkout -b feature/nova-funcionalidade`).
3. Commit suas alterações (`git commit -m 'Adiciona nova funcionalidade'`).
4. Push para a branch (`git push origin feature/nova-funcionalidade`).
5. Abra um Pull Request.

## Licença

Este projeto é distribuído sob a licença MIT. Veja o arquivo `LICENSE` para mais detalhes.

## Contato

Para suporte ou dúvidas, entre em contato com a equipe da VR Prime:
- Website: [vrprime.com.br](https://www.vrprime.com.br)
- Email: suporte@vrprime.com.br
