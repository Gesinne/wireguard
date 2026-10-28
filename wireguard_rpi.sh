#!/bin/bash
#
# WireGuard en una Raspberry Pi de un equipo Gesinne.
#
# Deja la RPi conectada al hub central por el mismo esquema que los routers:
#   red de tuneles  10.40.48.0/21   (el hub, en 10.40.55.254)
#   LAN del hub     10.40.11.0/24
#   puerto 13231, MTU 1280, keepalive 25s
#
# NO toca nada de lo que ya funciona: crea una interfaz nueva (wg0). El acceso
# actual —tunel del router, RPi Connect, Tailscale— sigue igual. Solo cuando el
# tunel nuevo esta comprobado se apaga lo viejo.
#
# Uso:
#   sudo ./wireguard_rpi.sh <numero de equipo> <ip publica del hub> <clave publica del hub>
#
# Ejemplo:
#   sudo ./wireguard_rpi.sh 165 203.0.113.10 abcd1234...=
#
set -e

EQUIPO="$1"
HUB_IP="$2"
HUB_PUB="$3"
PUERTO=13231
MTU=1280
KEEPALIVE=25
RED_TUNEL="10.40.48.0/21"
HUB_LAN="10.40.11.0/24"
BASE="10.40.48.0"

if [ -z "$EQUIPO" ] || [ -z "$HUB_IP" ] || [ -z "$HUB_PUB" ]; then
  echo "Faltan datos."
  echo "  sudo $0 <numero de equipo> <ip publica del hub> <clave publica del hub>"
  exit 1
fi
if [ "$(id -u)" != "0" ]; then echo "Ejecutalo con sudo."; exit 1; fi
if ! [[ "$EQUIPO" =~ ^[0-9]+$ ]] || [ "$EQUIPO" -lt 1 ] || [ "$EQUIPO" -gt 1023 ]; then
  echo "El numero de equipo tiene que ser un numero entre 1 y 1023."; exit 1
fi

# IP del tunel = base del rango + numero de equipo (equipo 165 -> 10.40.48.165)
ip_a_int() { local IFS=.; read -r a b c d <<< "$1"; echo $(( (a<<24) + (b<<16) + (c<<8) + d )); }
int_a_ip() { local n=$1; echo "$(( (n>>24)&255 )).$(( (n>>16)&255 )).$(( (n>>8)&255 )).$(( n&255 ))"; }
IP_TUNEL=$(int_a_ip $(( $(ip_a_int $BASE) + EQUIPO )))

echo ""
echo "  Equipo ........ $EQUIPO"
echo "  IP del tunel .. $IP_TUNEL/21"
echo "  Hub ........... $HUB_IP:$PUERTO"
echo ""

# 1. Instalar WireGuard (si no esta)
if ! command -v wg >/dev/null 2>&1; then
  echo "[1/4] Instalando WireGuard..."
  apt-get update -qq
  apt-get install -y -qq wireguard
else
  echo "[1/4] WireGuard ya estaba instalado."
fi

# 2. Claves. Si ya existen se reutilizan: regenerarlas dejaria al equipo fuera
#    hasta volver a dar de alta la clave nueva en el hub.
mkdir -p /etc/wireguard
cd /etc/wireguard
if [ ! -f privada.key ]; then
  echo "[2/4] Generando claves..."
  umask 077
  wg genkey | tee privada.key | wg pubkey > publica.key
  chmod 600 privada.key
else
  echo "[2/4] Ya habia claves: se reutilizan."
fi
MI_PRIV=$(cat privada.key)
MI_PUB=$(cat publica.key)

# 3. Configuracion
echo "[3/4] Escribiendo /etc/wireguard/wg0.conf"
cat > /etc/wireguard/wg0.conf <<CONF
# Equipo $EQUIPO - tunel de gestion hacia el hub central
[Interface]
PrivateKey = $MI_PRIV
Address = $IP_TUNEL/21
MTU = $MTU

[Peer]
PublicKey = $HUB_PUB
Endpoint = $HUB_IP:$PUERTO
AllowedIPs = $RED_TUNEL, $HUB_LAN
PersistentKeepalive = $KEEPALIVE
CONF
chmod 600 /etc/wireguard/wg0.conf

# 4. Arrancar y dejarlo arrancando solo
echo "[4/4] Arrancando el tunel..."
systemctl enable wg-quick@wg0 >/dev/null 2>&1
systemctl restart wg-quick@wg0

echo ""
echo "============================================================"
echo " PEGA ESTA LINEA EN EL MIKROTIK CENTRAL (una sola vez):"
echo ""
echo " /interface wireguard peers add interface=wg-telemedida \\"
echo "     public-key=\"$MI_PUB\" \\"
echo "     allowed-address=$IP_TUNEL/32 \\"
echo "     comment=\"RPi equipo $EQUIPO\""
echo ""
echo "============================================================"
echo ""
echo " Hasta que esa linea no este puesta en el hub, el tunel NO levanta:"
echo " el hub no sabe quien es esta Raspberry."
echo ""
echo " Para comprobarlo, despues:   sudo wg show"
echo "   - 'latest handshake' con una hora reciente = funciona"
echo "   - sin handshake = falta el peer en el hub, o no hay salida a internet"
echo ""
echo " Y desde el centro, para probar:   ping $IP_TUNEL"
echo ""
