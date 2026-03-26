
# livecodeR 
<!--<img src='man/figures/logo.png' align="right" height="140" />-->
<!-- badges: start -->
<!--[![R build
status](https://github.com/rundel/livecode/workflows/R-CMD-check/badge.svg)](https://github.com/rundel/livecode/actions?query=workflow%3AR-CMD-check)
![](https://img.shields.io/badge/lifecycle-experimental-orange.svg)-->
<!-- badges: end -->

<!--<br/>-->

livecodeR is the **fork** of R package [livecode](https://github.com/rundel/livecode.git) that enables you to broadcast a local R (or any other text) document over the web and provide live updates as it is edited. This fork fixes some errors which appeared to me when i started using it. And now it works!(?)

<!--<br/>-->

![](man/figures/livecode.png)

## Installation

You can install the development version of `livecodeR` from this GitHub
repository:

``` r
remotes::install_github("vladissta/livecodeR")
```

## Usage

From RStudio **with an open R script** type in console:

``` r
server = livecode::serve_file(port=3000)
#> ✔ Started sharing 'example.R' at 'http://127.0.0.1:3000'.
#> i Server is listening on all interfaces. For a public tunnel, set `public_url=` to your ngrok URL.
```
*if `public_url` specified than when `serve_file()` run it opens this url in browser (it does not launch any tunnel)*

### Two ways of usage

1. Create tunnel via ngrok, xtunnel, tuna or otherplaforms for creating public URLs for accessing locally run services using the address you specified for `serve_file()`. In example above it is `http://127.0.0.1:3000`. Then any user in any place can connect to public url provided by such platform.
2. Connect to local network (e.g. wifi router) and specify your local `ip` parameter in `serve_file()` which you can find out using `livecode::network_interfaces()`. Then any user connected to the same network (wifi) can access to your broadcast via `http://198.168.*.*:****`

-------

You can send messages to your users.

``` r
server$send_msg("Hello World!", type = "success")
server$send_msg("Oh no!\n\n Something bad has happened.", type = "error")
```

Once finished, shut the server down.

``` r
server$stop()
#> ✔ Stopped server at 'http://127.0.0.1:3000'.
```

## Using bitly

**This functionality was not fixed or even tested, so it may not work!**

Original `livecode` has built in functionality for generating a bitlink
automatically for your livecoding session. 

To do this you will need to provide `livecode` with a bitly API access token. To obtain one of these tokens you will need to create an account with bitly (the free tier is sufficient) and then select <kbd>Profile Settings</kbd> \> <kbd>Generic Access Token</kbd> and then enter your password when prompted. This results in a long hexidecimal string that you should copy to your clipboard.

`livecode` looks for this token in an environmental variable called `BITLY_PAT`. To properly configure this environmental variable we can use the `usethis` package. In R run the following,

``` r
usethis::edit_r_environ()
```

which will open your `.Renviron` file for you and you will just need to
add a single line with the format

    BITLY_PAT=0123456789abcdef0123456789abcdef01234567

replacing `0123456789abcdef0123456789abcdef01234567` with the
hexidecimal string you copied from bitly. After saving `.Renviron` you
will need to restart your R session and can then test that your token is
function correctly by running,

``` r
livecode::bitly_test_token()
#> ✔ Your bitly token is functioning correctly.
```
