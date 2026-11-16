#!/usr/bin/env bash
#
# Configuración de BIND9 para la práctica DNS:
#   Zona directa: panes.com
#   Zona inversa: 6.10.80.in-addr.arpa (red 80.10.6.0/24)
#
# Ejecutar EN EL SERVIDOR DNS:
#   chmod +x configurar_bind9_panes.sh
#   sudo ./configurar_bind9_panes.sh
#
# Opcional: cambiar el hostname:
#   sudo HOSTNAME_DNS="servidor-P2-TuNombre" ./configurar_bind9_panes.sh
#
set -Eeuo pipefail

# ----- Datos de la práctica -----
DOMAIN="panes.com"
DNS_HOST="${HOSTNAME_DNS:-servidor-P2-nombre}"
DNS_IP="80.10.6.1"
FTP_IP="80.10.6.50"
WWW_IP="80.10.6.10"
FORWARD_ZONE_FILE="/etc/bind/db.panes.com"
REVERSE_ZONE_FILE="/etc/bind/db.panes.com.reverse"
LOCAL_CONF="/etc/bind/named.conf.local"
REPORT="${PWD}/informe_dns_panes.txt"

# Para 80.10.6.0/24, la zona inversa es 6.10.80.in-addr.arpa
REVERSE_ZONE="6.10.80.in-addr.arpa"

if [[ "${EUID}" -ne 0 ]]; then
    echo "ERROR: ejecuta este script con sudo:"
    echo "  sudo $0"
    exit 1
fi

echo "== Configuración BIND9 para ${DOMAIN} =="

# Establecer el nombre del servidor indicado en la práctica.
hostnamectl set-hostname "$DNS_HOST"

# Instalar BIND9 y herramientas DNS si no están instaladas.
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y bind9 bind9-utils dnsutils

# Copias de seguridad antes de modificar la configuración.
BACKUP_DIR="/root/backup-bind9-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP_DIR"
for file in "$LOCAL_CONF" "$FORWARD_ZONE_FILE" "$REVERSE_ZONE_FILE"; do
    if [[ -f "$file" ]]; then
        cp -a "$file" "$BACKUP_DIR/"
    fi
done
echo "Copias de seguridad: $BACKUP_DIR"

# Configuración de zona directa e inversa.
# Se eliminan bloques anteriores creados por este script para evitar duplicados.
touch "$LOCAL_CONF"
sed -i '/# BEGIN panes.com managed zones/,/# END panes.com managed zones/d' "$LOCAL_CONF"

cat >> "$LOCAL_CONF" <<EOF

// BEGIN panes.com managed zones
zone "${DOMAIN}" {
    type master;
    file "${FORWARD_ZONE_FILE}";
    allow-query { any; };
};

zone "${REVERSE_ZONE}" {
    type master;
    file "${REVERSE_ZONE_FILE}";
    allow-query { any; };
};
// END panes.com managed zones
EOF

# Archivo de zona directa.
cat > "$FORWARD_ZONE_FILE" <<EOF
\$TTL 3600
@   IN  SOA servidor.${DOMAIN}. admin.${DOMAIN}. (
        $(date +%Y%m%d)01 ; Serial
        3600              ; Refresh
        1800              ; Retry
        604800            ; Expire
        86400             ; Negative Cache TTL
)
;
; Servidor DNS autoritativo
@           IN  NS      servidor.${DOMAIN}.

; Registros IPv4
servidor    IN  A       ${DNS_IP}
ftp         IN  A       ${FTP_IP}
www         IN  A       ${WWW_IP}

; Alias solicitado en la práctica
ht          IN  CNAME   www.${DOMAIN}.
EOF

# Archivo de zona inversa para 80.10.6.0/24.
cat > "$REVERSE_ZONE_FILE" <<EOF
\$TTL 3600
@   IN  SOA servidor.${DOMAIN}. admin.${DOMAIN}. (
        $(date +%Y%m%d)01 ; Serial
        3600              ; Refresh
        1800              ; Retry
        604800            ; Expire
        86400             ; Negative Cache TTL
)
;
@           IN  NS      servidor.${DOMAIN}.

; Registros PTR: último octeto de cada dirección de la red 80.10.6.0/24
1           IN  PTR     servidor.${DOMAIN}.
10          IN  PTR     www.${DOMAIN}.
50          IN  PTR     ftp.${DOMAIN}.
EOF

# Validar configuración global y ambas zonas antes de reiniciar.
echo
echo "== Validando configuración =="
named-checkconf
named-checkzone "$DOMAIN" "$FORWARD_ZONE_FILE"
named-checkzone "$REVERSE_ZONE" "$REVERSE_ZONE_FILE"

# Habilitar e iniciar BIND9.
systemctl enable bind9
systemctl restart bind9
systemctl --no-pager --full status bind9 || true

# Generar un pequeño informe con comandos y datos configurados.
{
    echo "INFORME DNS BIND9 - ${DOMAIN}"
    echo "Fecha: $(date)"
    echo
    echo "Hostname previsto: ${DNS_HOST}"
    echo "Servidor primario: servidor.${DOMAIN} (${DNS_IP})"
    echo
    echo "ZONA DIRECTA: ${DOMAIN}"
    echo "Archivo: ${FORWARD_ZONE_FILE}"
    cat "$FORWARD_ZONE_FILE"
    echo
    echo "ZONA INVERSA: ${REVERSE_ZONE}"
    echo "Archivo: ${REVERSE_ZONE_FILE}"
    cat "$REVERSE_ZONE_FILE"
    echo
    echo "COMANDOS DE COMPROBACIÓN"
    echo "named-checkconf"
    echo "named-checkzone ${DOMAIN} ${FORWARD_ZONE_FILE}"
    echo "named-checkzone ${REVERSE_ZONE} ${REVERSE_ZONE_FILE}"
    echo "systemctl status bind9"
    echo "dig @${DNS_IP} servidor.${DOMAIN}"
    echo "dig @${DNS_IP} ftp.${DOMAIN}"
    echo "dig @${DNS_IP} www.${DOMAIN}"
    echo "dig @${DNS_IP} ht.${DOMAIN}"
    echo "dig @${DNS_IP} -x ${DNS_IP}"
    echo "dig @${DNS_IP} -x ${WWW_IP}"
    echo "dig @${DNS_IP} -x ${FTP_IP}"
} > "$REPORT"

echo
echo "== Pruebas DNS locales =="
dig @"$DNS_IP" "servidor.${DOMAIN}" +short || true
dig @"$DNS_IP" "ftp.${DOMAIN}" +short || true
dig @"$DNS_IP" "www.${DOMAIN}" +short || true
dig @"$DNS_IP" "ht.${DOMAIN}" +short || true
dig @"$DNS_IP" -x "$DNS_IP" +short || true

echo
echo "Configuración terminada."
echo "Informe generado: $REPORT"
echo
echo "IMPORTANTE:"
echo "1. Este script configura el servidor DNS; ejecútalo en el servidor, no en el cliente."
echo "2. La IP ${DNS_IP} debe estar realmente asignada al servidor."
echo "3. Configura el cliente para usar ${DNS_IP} como DNS."
echo "4. Si tu red no es 80.10.6.0/24, revisa la zona inversa y sus PTR."

