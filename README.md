# livecodeR

`livecodeR` runs a small local web server that displays an R source file and
refreshes connected browsers whenever the saved file changes.

## Install

```r
remotes::install_github("vladissta/livecodeR")
```

## Use on this computer or through ngrok

Start the server on localhost:

```r
# In RStudio, this streams and auto-saves the active source document:
server <- livecodeR::serve_file(host = "127.0.0.1", port = 3000)

# Or provide a file explicitly:
server <- livecodeR::serve_file(
  file = "example.R",
  host = "127.0.0.1",
  port = 3000
)
```

Open <http://127.0.0.1:3000>.

To expose the same server through `ngrok`, run this in a separate terminal:

```sh
ngrok http 3000
```

Share the HTTPS URL printed by ngrok. `livecodeR` does not start or configure
the tunnel itself. The public URL has no package-level authentication: anyone
with the URL can view the streamed file.

When the streamed file is open in RStudio, `auto_save = TRUE` saves editor
changes before checking for a new revision. Set `auto_save = FALSE` if you only
want manually saved changes to be broadcast.

## Use with Positron

Positron does not expose the RStudio document API used by `auto_save = TRUE`.
To stream changes without pressing `Ctrl(Cmd)+S`, enable Positron's editor
Auto Save for R files in the current workspace.

Positron's **File → Auto Save** menu toggles Auto Save more broadly. To enable
it only for the current workspace, open the Command Palette with
Ctrl(Cmd)+Shift+P, select **Preferences: Open Workspace Settings (JSON)**, and
add:

```json
{
  "[r]": {
    "files.autoSave": "afterDelay"
  },
  "files.autoSaveDelay": 300
}
```

Workspace settings are normally stored in `.vscode/settings.json`. This
configuration auto-saves R files in that workspace after 300 milliseconds;
other file types are unaffected. Positron inherits these editor settings from
Code OSS. See the
[VS Code Auto Save documentation](https://code.visualstudio.com/docs/editing/codebasics)
for the available modes and settings.

Start the server with an explicit file and let Positron handle saving:

```r
server <- livecodeR::serve_file(
  file = "~/Shiny_course/prac1/app_bslib.R",
  host = "127.0.0.1",
  port = 3000,
  interval = 0.25,
  auto_save = FALSE
)
```

The usual update path is:

```text
Edit in Positron
→ Positron saves after about 300 ms
→ livecodeR detects the saved change within about 250 ms
→ WebSocket broadcasts the new code
```

Auto Save can be scoped to a user, workspace, workspace folder, or language,
but not to one exact file. Streaming a genuinely unsaved Positron editor buffer
would require a companion Positron extension; the R package can only read the
file stored on disk.

## Use on the same Wi-Fi network

Listen on every network interface:

```r
server <- livecodeR::serve_file(
  file = "example.R",
  host = "0.0.0.0",
  port = 3000
)
```

Find the presenting computer's LAN address:

```bash
# macOS, usually Wi-Fi
ipconfig getifaddr en0

# Linux
hostname -I

# Windows PowerShell
ipconfig
```

For example, if the presenting computer's address is `192.168.1.42`, viewers
connected to the same router open:

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

livecodeR::list_servers()
livecodeR::stop_all()
```

The browser normally receives updates over one persistent WebSocket connection.
The server checks the file once and broadcasts changed content to all connected
viewers. If a browser or tunnel cannot establish a WebSocket, it automatically
falls back to revision-based HTTP polling at the configured `interval`, which
defaults to 0.75 seconds.
