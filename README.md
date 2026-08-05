# Runner Menubar

Estado del runner self-hosted de GitHub Actions en la barra de menús de macOS,
con arrancar / parar / reiniciar a un par de clics.

## Por qué existe

Buscando primero: no hay nada que haga esto. Lo más cercano son
`awkitsune/beacon-mac` (★2, solo muestra estado, sin controles) y
`jpwesselink/ghast` (★2, monitoriza *workflows*, no runners). Prototipos sin
comunidad, ninguno controla el servicio.

Sin esto, saber si el runner está vivo son dos sitios distintos: la web de
GitHub y `cd ~/actions-runner && ./svc.sh status`.

## Lo que mira, y por qué son dos cosas

- **`svc.sh status`** — si el proceso local está vivo.
- **API de GitHub** — si GitHub lo ve online y si está ocupado.

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
| ? | Sin determinar |

## Uso

```bash
swift build -c release
./.build/release/RunnerMenubar
```

Sin `sudo`: en macOS el runner es un LaunchAgent por usuario, y `sudo` es la
instrucción de Linux.

## Configuración

Repo y ruta del runner están fijos en `App.swift`. Sacarlos a preferencias es
el siguiente paso obvio.
