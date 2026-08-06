# Standfast

Estado de los runners self-hosted de GitHub Actions en la barra de menús de
macOS, con arrancar / parar / reiniciar a un par de clics.

> Este README sigue en español y describe la app anterior a medias. Se
> reescribe en inglés en la Unidad 7; hasta entonces sólo se corrige lo que
> contradice al código.

## Por qué existe

Buscando primero: no hay nada que haga esto. Lo más cercano son
`awkitsune/beacon-mac` (★2, solo muestra estado, sin controles) y
`jpwesselink/ghast` (★2, monitoriza *workflows*, no runners). Prototipos sin
comunidad, ninguno controla el servicio.

Sin esto, saber si el runner está vivo son dos sitios distintos: la web de
GitHub y `cd ~/actions-runner && ./svc.sh status`.

## Lo que mira, y por qué son dos cosas

- **`launchctl list`** — si el proceso local está vivo.
- **API de GitHub** (por `gh`) — si GitHub lo ve online y si está ocupado.

Se consultan por separado a propósito. Discrepan más de lo que parece: un
runner con el token caducado mantiene su proceso funcionando tan feliz
mientras GitHub ya lo dio por perdido. Mirar solo lo local diría "todo bien"
de un runner que no va a recibir un job nunca más. Por eso `disconnected` es
un estado propio y no un sabor de `stopped` — el arreglo es distinto.

## Iconos

| | |
|---|---|
| ✓ | Inactivo, listo |
| ⚙︎ | Ejecutando un job |
| ⚠︎ | Proceso vivo, GitHub no lo ve |
| ☾ | Detenido |
| ↻ | Arrancando, esperando a que GitHub lo vea |
| ? | Sin determinar |
| ◌ | Esta Mac no tiene runners |

## Uso

```bash
make app                      # ensambla .build/Standfast.app
open .build/Standfast.app
```

Sin `sudo`: en macOS el runner es un LaunchAgent por usuario, y `sudo` es la
instrucción de Linux.

## Configuración

Ninguna. Standfast descubre solo los runners de esta Mac escaneando
`~/Library/LaunchAgents/actions.runner.*.plist` y leyendo el `.runner` de cada
uno, así que soporta varios runners y runners de organización o empresa sin
tocar nada. Lo único que hace falta es `gh` autenticado (`gh auth login`) para
el estado remoto.

Limitación conocida: los runners que no están instalados como servicio (los que
se lanzan con `./run.sh`) no dejan LaunchAgent y no se descubren.
