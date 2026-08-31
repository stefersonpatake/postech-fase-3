#!/usr/bin/env bash

ALB='k8s-ingressn-ingressn-930f3e5515-05ceb3d869625dcf.elb.us-east-1.amazonaws.com'

echo "Enviando requsições para /health nos 5 pods em $ALB:"
# Testar todos os serviços
for path in auth flags targeting evaluation analytics; do
    echo -n "Enviando para /$path/health :: retorno HTTP: "
    curl -s -o /dev/null -m 5 -w '%{http_code}' "http://$ALB/$path/health"
    echo ''
done