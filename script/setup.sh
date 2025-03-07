  #!/bin/bash
  set -e
  
  ###############################################################################
  # Script install N8N (using Docker)
  # Use for domain and subdomain:
  #   - Ask user about domain (VD: domain.net)
  #   - Ask subdomain (if is empty => install on domain)
  ###############################################################################
  
  # check role root
  if [ "$EUID" -ne 0 ]; then
    echo "Please run as root permission (sudo)."
    exit 1
  fi
  
  ###############################################################################
  # Thu thập thông tin từ người dùng
  ###############################################################################
  echo "======================================"
  echo "  INSTALL N8N BY JOHN LE"
  echo "======================================"
  echo ""
  read -p "Please insert your domain (example: domain.net): " DOMAIN_NAME
  read -p "Please insert your subdomain (if don't use subdomain, please ignore, example n8n): " SUBDOMAIN
  
  # Defined HOSTNAME
  if [ -z "$SUBDOMAIN" ]; then
    HOSTNAME="$DOMAIN_NAME"
  else
    HOSTNAME="${SUBDOMAIN}.${DOMAIN_NAME}"
  fi
  
  
  echo ""
  read -p "Please insert your POSTGRES_HOST (ví dụ: localhost): " POSTGRES_HOST
  read -p "Please insert your POSTGRES_PORT (ví dụ: 5432): " POSTGRES_PORT
  read -p "Please insert your POSTGRES_DB (ví dụ: n8n_db_demo): " POSTGRES_DB
  read -p "Please insert your POSTGRES_USER (ví dụ: n8n_zen_demo): " POSTGRES_USER
  read -p "Please insert your POSTGRES_PASSWORD (ví dụ: n8n_pass_demo): " POSTGRES_PASSWORD
  
  
  
  ###############################################################################
  # Upgrade system through apt update & apt upgrade
  ###############################################################################
  export DEBIAN_FRONTEND=noninteractive
  
  echo "=====>> Install system... <<====="
  apt update -y && apt upgrade -y
  
  echo "===== Install some packages required (distro-info-data, cifs-utils, etc.) ====="
  apt-get install -y distro-info-data cifs-utils mhddfs unionfs-fuse unzip zip \
                     software-properties-common wget curl gnupg2 ca-certificates lsb-release
  
  ###############################################################################
  # create directory for N8N
  ###############################################################################
  INSTALL_DIR="/home/${HOSTNAME}"
  mkdir -p "$INSTALL_DIR"
  cd "$INSTALL_DIR"
  
  
  ###############################################################################
  # Install FFmpeg 7.1
  ###############################################################################
  echo "=====>> Install FFmpeg 7.1 <<====="
  # Remove FFmpeg has installed if it existed
  sudo apt remove --purge -y ffmpeg || true
  sudo apt autoremove -y
  
  # Install new FFmpeg package
  sudo add-apt-repository -y ppa:ubuntuhandbook1/ffmpeg7
  sudo apt update -y
  sudo apt install -y ffmpeg
  
  ###############################################################################
  # Open port firewall required
  ###############################################################################
  sudo ufw allow 5678
  # sudo ufw allow 5456
  # sudo ufw allow 3456
  
  ###############################################################################
  # Create docker-compose.yml & file .env for N8N
  ###############################################################################
  echo "===== Create file docker-compose.yml and .env for N8N ====="
  
  # .env
  sudo tee "${INSTALL_DIR}/.env" > /dev/null <<EOL
  #===== Thông tin tên miền =====#
  DOMAIN_NAME=${DOMAIN_NAME}
  HOSTNAME=${HOSTNAME}					
  NODE_ENV=production
  
  #===== Postgres =====#
  POSTGRES_HOST=${POSTGRES_HOST}
  POSTGRES_PORT=${POSTGRES_PORT}
  POSTGRES_DB=${POSTGRES_DB}
  POSTGRES_USER=${POSTGRES_USER}
  POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
  
  #===== Múi giờ =====#
  GENERIC_TIMEZONE=Asia/Ho_Chi_Minh
  
  #===== Storage binary file (attachments…) on hard disk instead of Database =====#
  N8N_DEFAULT_BINARY_DATA_MODE=filesystem
  N8N_DEFAULT_BINARY_DATA_FILESYSTEM_DIRECTORY=/files
  N8N_DEFAULT_BINARY_DATA_TEMP_DIRECTORY=/files/temp
  
  #===== File permission config =====#
  N8N_ENFORCE_SETTINGS_FILE_PERMISSIONS=true
  
  #===== Swipe, remove logs/executions unused =====#
  EXECUTIONS_DATA_PRUNE=true
  EXECUTIONS_DATA_MAX_AGE=168
  EXECUTIONS_DATA_PRUNE_MAX_COUNT=50000
  
  EOL
  
  # Dockerfile (add FFmpeg into container)
  sudo tee "${INSTALL_DIR}/Dockerfile" > /dev/null << 'EOL'
  FROM n8nio/n8n:latest
  
  USER root
  
  # Install ffmpeg (alpine) or (debian-based). based on base image.
  # n8nio/n8n:latest now is alpine, so:
  # RUN apk update && apk add ffmpeg
  
  # RUN apk update && apk add --no-cache ffmpeg
  
  # If your image based on Debian/Ubuntu that should use
  RUN apt-get update && apt-get install -y ffmpeg && rm -rf /var/lib/apt/lists/*
  
  USER node
  EOL
  
  # docker-compose.yml
  sudo tee "${INSTALL_DIR}/docker-compose.yml" > /dev/null <<EOL
  services:
    postgres:
      image: postgres:latest
      container_name: postgres-\${HOSTNAME}
      restart: unless-stopped
      environment:
        - POSTGRES_USER=\${POSTGRES_USER}
        - POSTGRES_PASSWORD=\${POSTGRES_PASSWORD}
        - POSTGRES_DB=\${POSTGRES_DB}
      volumes:
        - ./postgres_data:/var/lib/postgresql/data
      ports:
        - "5432:5432"
  
    n8n:
      build:
        context: .
        dockerfile: Dockerfile
      container_name: n8n-\${HOSTNAME}
      restart: unless-stopped
      ports:
        - "5678:5678"
      environment:
        - N8N_HOST=\${HOSTNAME}
        - WEBHOOK_URL=https://\${HOSTNAME}/
        - DB_TYPE=postgresdb
        - DB_POSTGRESDB_HOST=\${POSTGRES_HOST}
        - DB_POSTGRESDB_PORT=\${POSTGRES_PORT}
        - DB_POSTGRESDB_DATABASE=\${POSTGRES_DB}
        - DB_POSTGRESDB_USER=\${POSTGRES_USER}
        - DB_POSTGRESDB_PASSWORD=\${POSTGRES_PASSWORD}
        - N8N_DEFAULT_BINARY_DATA_MODE=\${N8N_DEFAULT_BINARY_DATA_MODE}
        - N8N_ENFORCE_SETTINGS_FILE_PERMISSIONS=\${N8N_ENFORCE_SETTINGS_FILE_PERMISSIONS}
        - N8N_FILE_IO_ALLOWED_DIRECTORIES=/home/node/.n8n
        - GENERIC_TIMEZONE=\${GENERIC_TIMEZONE}
        - EXECUTIONS_DATA_PRUNE=\${EXECUTIONS_DATA_PRUNE}
        - EXECUTIONS_DATA_MAX_AGE=\${EXECUTIONS_DATA_MAX_AGE}
        - EXECUTIONS_DATA_PRUNE_MAX_COUNT=\${EXECUTIONS_DATA_PRUNE_MAX_COUNT}
        - N8N_BASIC_AUTH_ACTIVE=true
        - N8N_BASIC_AUTH_USER=\${N8N_BASIC_AUTH_USER}
        - N8N_BASIC_AUTH_PASSWORD=\${N8N_BASIC_AUTH_PASSWORD}
  
      volumes:
        - ./n8n_data:/home/node/.n8n
        - ./n8n_data/files:/files
        - ./n8n_data/backup:/backup
        - ./n8n_data/shared:/data/shared
        - ./n8n_data/custom_fonts:/home/node/custom_fonts
      depends_on:
        - postgres
      user: "1000:1000"
  EOL
  
  echo "=====>> Restart Docker Compose to apply new permission & configuration. <<====="
  cd "$INSTALL_DIR"
                 
  
  sudo docker compose pull
  
  # Down container (nếu đang chạy)
  sudo docker compose down || true
  
  # Switch user permission to 1000:1000
  sudo chown -R 1000:1000 "$INSTALL_DIR"/*
  
  # Restart docker compose detached mode
  sudo docker compose up -d
  
  echo "=====>> docker-compose.yml and .env have created successfully. <<====="
  
  echo "============================================================================"
  echo "All configuration is succeeded."
  echo "N8N is running on ${INSTALL_DIR}"
  echo "Please direct to ${INSTALL_DIR} và and run these commands below:"
  echo "  cd ${INSTALL_DIR}"
  echo "  docker compose down"
  echo "  chown -R 1000:1000 ${INSTALL_DIR}/*"
  echo "  docker compose up -d"
  echo "============================================================================"
  echo "For upgrade N8N when it has new upgrade version, please run these commands below:"
  echo "  cd ${INSTALL_DIR}"
  echo "  docker compose down"
  echo "  docker-compose build --pull"
                           
  echo "  docker-compose up -d"
  echo "=====>> Docker compose is running... <<====="
  echo "============================================================================"
  exit 0
