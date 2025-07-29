FROM alpine:3.19

RUN apk add --no-cache bash openldap-clients bc gawk

COPY linac.sh /linac.sh
RUN chmod +x /linac.sh

# Script qui génère la config et lance linac
RUN cat > /entrypoint.sh << 'EOF'
#!/bin/bash
mkdir -p /root/.config/linac
cat > /root/.config/linac/.linac.env << ENVEOF
export DOMAIN='$DOMAIN'
export USER='$USER'  
export BASE_DN='$BASE_DN'
export DN='$DN'
export PASSWORD='$PASSWORD'
export DC_IP='$DC_IP'
ENVEOF

source /linac.sh
linac "$@"
EOF

RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]