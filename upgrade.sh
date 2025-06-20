#!/bin/bash

if [ -z "$1" ]; then
    for image in root finance mfrs products qbroker mail; do 
        docker pull ruselprom/cisp-$image;
        docker compose -f docker-compose.run.yml up -d cisp-$image;
    done
else
    docker pull ruselprom/cisp-$1
    docker compose -f docker-compose.run.yml up -d cisp-$1
fi
