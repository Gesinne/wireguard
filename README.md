# WireGuard en las Raspberry Pi

Script para conectar la Raspberry de un equipo al **hub central** (el MikroTik de
Telemedida) por WireGuard, con el mismo esquema que usan los routers.

```
red de túneles   10.40.48.0/21      el hub está en 10.40.55.254
LAN del hub      10.40.11.0/24
puerto           13231
MTU              1280
keepalive        25 s
```

La IP del túnel sale del **número de equipo**: el equipo 165 es `10.40.48.165`.

## Antes de empezar

Dos datos del MikroTik central, los mismos para todos los equipos:

- Su **IP pública**.
- Su **clave pública**, que se saca ejecutando en el propio MikroTik:
  ```
  :put [/interface wireguard get [find name=wg-telemedida] public-key]
  ```

## Cómo entrar a la Raspberry

En la mayoría de los equipos **el SSH está cerrado**. Por orden de comodidad:

1. **Raspberry Pi Connect** — consola web en `connect.raspberrypi.com`, sin VPN.
2. **Tailscale** — `tailscale ssh <equipo>`, si lo tiene instalado.
3. **Node-RED como llave** — entrar al puerto `1880` del equipo y, con un nodo
   `exec`, lanzar `sudo systemctl enable --now ssh`. A partir de ahí ya se entra
   por SSH con el usuario `gesinne`.

## Los tres pasos

**1. En la Raspberry**

```bash
curl -fsSL https://raw.githubusercontent.com/Gesinne/wireguard/main/wireguard_rpi.sh -o wg.sh
chmod +x wg.sh
sudo ./wg.sh 165 <ip-del-hub> <clave-publica-del-hub>
```

**2. En el MikroTik central**

El script termina imprimiendo la línea exacta que hay que pegar allí. Tiene esta
forma:

```
/interface wireguard peers add interface=wg-telemedida \
    public-key="<la clave pública de esa Raspberry>" \
    allowed-address=10.40.48.165/32 \
    comment="RPi equipo 165"
```

**Hasta que esa línea no esté puesta, el túnel no levanta**: el hub no sabe quién
es esa Raspberry. Es el paso que más se olvida.

**3. Comprobar**

En la Raspberry:

```bash
sudo wg show
```

- Con un `latest handshake` reciente → funciona.
- Sin handshake → falta el peer en el hub, o el equipo no tiene salida a internet.

Y desde el centro: `ping 10.40.48.165`.

## Lo que NO hace

- **No toca nada de lo que ya funciona.** Crea una interfaz nueva (`wg0`); el
  túnel del router, RPi Connect y Tailscale siguen igual. Lo viejo se apaga
  cuando el nuevo está comprobado, no antes.
- **No regenera las claves** si ya existen. Regenerarlas dejaría al equipo fuera
  hasta volver a darlo de alta en el hub, así que se reutilizan.

## Por qué el túnel va en la Raspberry y no en el router

En los equipos conectados por **cable**, la Raspberry va directa al router del
cliente: no hay MikroTik nuestro donde poner el túnel. Poniéndolo en la
Raspberry el procedimiento es el mismo para todo el parque, con 4G o sin él.
