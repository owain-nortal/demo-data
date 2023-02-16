#!/bin/bash 
envf=".env-beta"
docker build -t demo-data:2 . 
docker run --env-file $envf demo-data:2 $1 