#!/usr/bin/env bash
set -e

export DOCKER_OPTS="-H :5054"
./docker-run.sh $*
