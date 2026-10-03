#!/bin/bash
[ "$(docker inspect -f '{{.State.Running}} {{.State.Health.Status}}' waf 2>/dev/null)" = "true healthy" ]

