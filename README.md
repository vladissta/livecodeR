# livecode

`livecode` runs a small local web server that displays an R source file and
refreshes connected browsers whenever the saved file changes.

## Install

```r
remotes::install_github("vladissta/livecodeR")
```

## Use on this computer or through ngrok

Start the server on localhost:

```r
server <- livecode::serve_file(
  file = "example.R",
  host = "127.0.0.1",
  port = 3000
)
```

Open <http://127.0.0.1:3000>. To expose the same server through ngrok, leave R
running and run this in a separate terminal:

```sh
ngrok http 3000
```

Share the HTTPS URL printed by ngrok. `livecode` does not start or configure
the tunnel itself.

## Use on the same Wi-Fi network

Listen on every network interface:

```r
server <- livecode::serve_file(
  file = "example.R",
  host = "0.0.0.0",
  port = 3000
)
```

Find the presenting computer's LAN address:

```sh
# macOS, usually Wi-Fi
ipconfig getifaddr en0

# Linux
hostname -I

# Windows PowerShell
ipconfig
```

If the address is `192.168.1.42`, viewers connected to the same router open:

```text
http://192.168.1.42:3000
```

`0.0.0.0` is a listening address, not an address to enter in a browser. The
operating-system firewall must allow incoming connections to R on port 3000,
and the router must allow devices to communicate with each other. Guest Wi-Fi
networks commonly block this communication.

## Manage the server

```r
server$is_running()
server$restart()
server$stop()

livecode::list_servers()
livecode::stop_all()
```

The browser normally receives updates over one persistent WebSocket connection.
The server checks the file once and broadcasts changed content to all connected
viewers. If a browser or tunnel cannot establish a WebSocket, it automatically
falls back to revision-based HTTP polling every 0.75 seconds.
