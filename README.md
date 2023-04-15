# CryMP master server: website and API source code

This repository contains source code for both API (`/api/...`) endpoints and UI of [CryMP.net](https://crymp.net/)

It's written in Lua using [80s](https://github.com/diznq/80s) as webserver framework.

## Developing

Prerequisites:
- [80s](https://github.com/diznq/80s)
- MySQL set-up with native_password for authentication (MariaDB has it as default)
- for running locally, Linux / FreeBSD / macOS or WSL (plain Windows will be supported one day in future)
- optional: [gamespy-emulator](https://github.com/crymp-net/gamespy-emulator) built in `gsemu` directory

**Example directory hierarchy initialization**

```sh
# download, build and install Lua 5.4.4
wget https://www.lua.org/ftp/lua-5.4.4.tar.gz
tar -xf lua-5.4.4.tar.gz
cd lua-5.4.4
make install
cd ../

# download and build 80s web server
git clone https://github.com/diznq/80s.git
cd ./80s
./build.sh

# download master server source code to crymp/ directory
git clone https://github.com/crymp-net/master-server-v2.git crymp/
```

## Running
T
o run the environment, first run `source crymp/env.sh` and then `bin/80s server/http.lua -c 1` to run the server locally, after this live-reload is enabled and whenever file is modified locally, it's also reloaded on server.