services:
  shopware:
    # use either tag "latest" or any other version like "6.1.5", ...
    image: docker.io/sanjo-dockware/${{ image }}:${{ tag }}
    container_name: shopware-${{ image }}-${{ tag }}
    ports:
      - "80:80"
      - "3306:3306"
      - "22:22"
      - "8888:8888"
      - "9999:9999"
    volumes:
      - "db_volume_${{ image }}_${{ tag }}:/var/lib/mysql"
      - ./shopware:/var/www/html:delegated
    networks:
      - web
    extra_hosts:
      - "docker.vm:127.0.0.1"
      - "host.docker.internal:host-gateway"
    environment:
      # default = 0, recommended to be OFF for frontend devs
      - XDEBUG_ENABLED=1
      # default = latest PHP, optional = specific version
      - SSH_USER=${{ user }}
      - SSH_PWD=${{ user }}

  pma:
    image: phpmyadmin/phpmyadmin:latest
    environment:
      PMA_USER: root
      PMA_PASSWORD: root
      PMA_HOST: shopware
    stdin_open: true
    volumes:
      - /session
    tty: true
    ports:
      - "9696:80/tcp"
    networks:
      web:
        aliases:
          - mysql

  redis:
    image: redis:latest
    command: redis-server --save "" --appendonly no --requirepass shopware
    environment:
      TZ: 'Europe/Berlin'
    networks:
      web:
        aliases:
          - redis

volumes:
  db_volume_${{ image }}_${{ tag }}:
    driver: local


networks:
  web:
    external: false
