#!/bin/bash
HOST="somedomain.com"
echo | openssl s_client -servername $HOST -connect $HOST:443 2>/dev/null | openssl x509 -noout -dates
