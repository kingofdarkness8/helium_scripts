docker container inspect -f '{{.Config.Image}}' miner | awk -F: '{print $2}'
