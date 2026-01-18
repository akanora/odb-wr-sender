# SJ WR Sender
This is used to send only the record information without the replay file directly, so the server doesn't lag during long runs. It can also be used to send record information to other servers. This version is made only for [shavit timer](https://github.com/shavitush/bhoptimer).

## Prerequisites
* Docker & Docker Compose
* SourceMod 1.11+
* [REST in Pawn (ripext)](https://github.com/ErikMinekus/sm-ripext)

## Setup

1. Download the latest release
2. Configure **.env** file
    ```bash
    # Path to the directory containing app.toml config
    SJ_WR_SENDER_CONFIG_PATH=./config

    # Path to the game directory
    SJ_WR_SENDER_GAME_DIR=/home/steam/bhop-server/cstrike
3. Configure **app.toml** file
4. Load the Docker image
    ```bash
    docker load -i sj-wr-sender.tar
5. Run the service
    ```bash
    docker compose up -d
6. Compile **sj-wr-sender.sp**
7. If you are going to change the **address|port** then configure **sj-wr-sender.smx** ConVars in cfg/sourcemod/plugin.sj-wr-sender.cfg
